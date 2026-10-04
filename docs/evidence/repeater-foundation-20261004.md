# Repeater foundation checks

Status: implemented locally, 2026-10-04. This is a CPU-only behavior and compatibility
foundation from frozen M09 `01912934`, not an accepted M10 lesson or selected
weapon presentation. Source checkpoint `2b867d3c` and integration assertions
`9941449c` / `05121e50` are local and unmerged.

## Actual behavior

The real server tests hold ordinary `Action.fire` with a finite shared Bullets
pool. Six warmup ticks produce no shot or ammunition consumption. The next
shots occur at ticks 7, 9 and 11, each resolving 14 direct damage through the
ordinary trace and record seams. A 60-Bullet pool becomes 57, target HP becomes
58, and the Repeater column records three attacks and 42 effective HP damage;
Rifle counts remain zero. Cover produces actual misses, the empty pool cannot
damage or draw successful-shot randomness, and resupply requires fresh warmup
after release. These constants remain feel candidates.

Actual weapon selection, input clearing, death, leave and mission retry reset
the private cycle. The shared controller uses genuine ownership and finite
ammunition. Default arcade equipment remains the prior three-gun kit. All six
physical keys retain their meanings, with repeated key 4 cycling the owned
Rifle/Repeater family.

## Strict contracts

Capability 35 rejects older humans, agents and spectators before Welcome on
a real development map that places a Repeater pickup. Current clients receive
MapInfo before snapshots. Participant record revision 2 requires eight weapon
columns; revision 1 keeps its exact five/six/seven-column shapes and refuses
even a zero eighth column. An older recipient gets revision 1 only when the
new counts are genuinely zero. Actual new counts refuse incompatible delivery
rather than being discarded. Standalone unversioned CombatCounts keeps its
historical width and refuses serialization with nonzero Repeater counts.

A separate real WebSocket probe used the retained `01912934` client equipment
and record validation bodies. Only their class declarations and dependency
binding were adjusted for isolated loading. Capability 34 received revision 1
with five columns, accepted by both retained and current validators. Capability
35 received revision 2 with eight columns, refused by the retained validator
and accepted by the current validator. The headless probe exited 0 with its
PASS marker and a clean log. Its privately owned native PID 26456 was cleaned.
Debug native SHA256:
`bca7162c2d7914c219a437291e49e470135ce6c4c6c2831fce3af0a272747ad7`.

Save version 11 uses the existing locked writer and exact strict version 10
reader. Tests retain a strict version 10 fixture's original bytes in an archive,
then reopen its explicit 39 HP, 17 armor, two grenades, three mines and recorded
M08 outcomes unchanged.
Valid historical version 2 through 10 fixtures are checked before forged new
ownership/selection is refused. Current stages through M09 cannot acquire
Repeater through a save or an existing full-arsenal kit. M10 remains pending.

## Verification state

Formatting, workspace all-target Clippy and the complete locked Rust workspace
pass. The server suite has 927 passing tests and three existing ignored tests;
all 17 real local-child integration tests pass. Focused equipment, records,
explosives and combat audio client harnesses pass cleanly. The audio regression
starts with an actual known gun cue, then verifies unsupported identities clear
the old stream instead of replaying it.

The matching private release build passes. The complete client checker passes
against that private binary: import, 255 scripts, all 119 harnesses, exit 0 and
no error lines. Actual M02 through M09 local-launch harnesses, retained history,
packaged-install checks and existing presentation contracts remain intact.
Its first complete run parsed all scripts and passed 118 of 119 harnesses.
The sole failure was a test still naming current client capability 34. The
corrected exact expectation is 35, while M08's own requirement stays 31. The
focused archive harness passes cleanly after that correction.
Release native SHA256:
`ec469482cfa336212c4a77e42bdea4fc683ec2d79f772f0310c0ca47056c3a58`.
Full combination CI, coverage, desktop packages and played feel are unclaimed.
No paid requests or GPU rendering ran. A real articulated Repeater asset,
truthful cues, strict presentation facts and an isolated played lesson remain
required before production selection. M10 crew transit and its map are outside
this foundation.

Earlier failed logs remain in private diagnostics: initial strict-shape and
actual reset assertions, the full workspace storage failure, and four current
writer assertions that still named version 10. The corrected assertions name
11 without changing historical fixtures, finite carry or child ownership.
The first full client log and its obsolete capability assertion are retained
separately from the complete repeat.
