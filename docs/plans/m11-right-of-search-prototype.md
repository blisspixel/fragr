# Right of Search prototype

Status: in flight, started 2026-10-05. This isolated leaf starts from the frozen
Common Carrier prototype `b0e6eb91`. Neither mission is finished-appearance or
fresh-player acceptance. The current main still refuses pending Right of Search.

## Goal

Build the Union custody tender from [the accepted level brief](../campaign/l11-right-of-search.md).
The reversal must read through entry from the Carrier, an orderly custody
working ship, a mineable bow-to-stern spine and a different stern return.
Pressure structure, occupied working rooms and controlled custody thresholds
must have actual collision and ordinary walking routes. A long main sightline
has short side loops and a parallel service route, rather than one empty hall.

The level's required new systems are actual separately counted Remote Mines
and the Redactor's observable distortion, commitment and decloak. Existing
proximity mines and enemy skins are not substitutes. An architectural checkpoint
is explicitly a non-mission development study until these systems, typed mission
   facts, persistence, presentation and played gates are implemented together.

## Canon and scope

The tender is practical industrial construction around 2070. Regular bone and
charcoal pressure surfaces distinguish it from the repaired Carrier. Black and
red identify issued uniforms, restraint machinery and seals, not every wall.
Observation windows keep the adjacent Carrier recognizable. Habitable rooms
are enclosed; vacuum and ship drift do not create new movement physics.

The entry armory teaches placement before the three-Clerk spine patrol.
Crew holds, a midpoint Turret and a parallel service crawlway provide flank
choices. The records room supports a distortion ambush among racks. A transfer
hold contains people, not collectible resources. Counter-boarders return down
the same spine; bridge control leads to the stern release and return umbilical.
At most two doors govern the route, with any optional restraint interaction
kept distinct from a door or mandatory escort. Sorrel's specific identity,
recognition scene and custody-schedule wording remain proposals. No new rescue
history or mandatory NPC arrival is invented here.

No paid generation, physics of decompression, zero gravity, general vehicle
motion, replacement cast, global material changes or unrelated multiplayer work.
Root owns shared documentation, publication and current allowance paragraphs.
The M10 ship-art leaf owns its furnishing and source geometry independently.

## Architecture and existing seams

1. Author a bounded custody-tender structural study under `server/maps/test/`.
   Reuse the strict authored loader, authoritative solids, explicit spawn feet,
   supplies and precomputed navigation. Give room loops enough headroom and
   real support; collision, ceiling and cover tests include exposed negative
   controls. It has no mission object, content promotion or playable M11 grant.
2. Implement Remote Mines through the counted explosive inventory, shared
   swept flight/contact and covered blast seams. Define independent placement
   and deliberate detonation policy, active-device limits, owner/death/round
   cleanup and actual counters before an M11 equipment grant. Gunfire never
   triggers a remote charge. Preserve every existing weapon index and gadget.
3. Implement Redactor through explicit hostile identity, authored encounter
   lifecycle and bounded navigation. Commitment and visual tell must precede
   attack, including when audio is muted. Preserve server-owned damage and
   contact; sprite effects convey existing facts rather than choosing stealth.
4. Add M11 typed map/state and controller through `maps/authored/m11.rs`,
   `protocol/m11.rs`, `mission/m11.rs` and `mission/controller/m11.rs`.
   Prepare all relevant worlds/navigation before readiness. Resend changed
   MapInfo before dependent state. Root reserved capability 37 and save version
   14 for the complete M11, Remote Mine and Redactor contract on 2026-10-05.
   The concurrent shot-occlusion fix uses existing fields and owns neither.
5. Reuse strict M10 entry carry and locked save promotion. No episode refill at
   M11, no retrospective crew facts, no pending mission granted by text alone.
   Historical bytes are validated and archived exactly. Root will review shared
   capability, protocol, controller and save hooks before composition.
6. Own `m11_mission_state.gd`, `m11_tender.gd`, M11 QA and keyed scene text.
   Reuse existing surface, panel, enemy, explosive, HUD and install seams.
   Actor sources stay their own separately reviewed asset lanes.

## Verification and acceptance

The first checkpoint requires strict-source boundary failures, actual standing
clearance, shot-blocking with open-lane controls, bidirectional navigation to
every required room/supply/return, and ordinary `GameState` integration with
no jump or teleport. It proves structure, not a playable mission or fun.

Remote Mine tests must exercise admission, finite stock, arming, deliberate
multi-charge trigger, gunfire nontrigger, blast cover, living body occlusion,
dead/left owner cleanup and resets. Redactor tests must exercise readable tell,
locked commitment, interruption/recovery, damage, cover, route budget and death.
Both use normal sim ticks and preserve current rules unless an intentional
revision is reviewed with matching client validation.

Mission tests require every ordered objective and actual stern departure,
finite equipment and actual counter-boarding outcomes; failure, continue,
M10-to-M11 carry, exact legacy migration and missing-current-source refusals.
Ordinary rendered play must inspect the Carrier landmark, ceiling enclosure,
spine/crawlway return, records-room distortion, mines and transfer-hold persons.
Headless checks do not prove readability, player learning or human fun.

Use a private target with two build jobs and an immutable matching native/client
pair. Before acceptance run focused owning suites, full workspace, warning-denied
Clippy, formatter, benchmark, coverage and complete matching client checker.
Root reviews the final composed source and requires all exact-head CI and three
desktop package gates before main. GPU captures need a coordinated lease;
all failures and exact owned process retirement remain evidence.

## Current checkpoint

The architectural source is implemented as a non-mission study,
`server/maps/test/m11_tender_structure.json`, ID 1111. It is not the canonical
M11 mission identity. Its 95 solids form a 20 by 64 metre pressure hull, a 4.4
metre spine, separate port service route, working holds, tall records racks,
raised bridge and distinct entry/stern umbilicals. Supported feet are 0.3 m on
the working deck and 1.5 m on the bridge, a 1.2 m ascent. Six existing finite
stocks are reachable; no substitute mines or actors are placed. Observation
windows and the adjacent Carrier remain required later presentation work; the
current pressure walls are opaque structural source, not false glass.

Five owning native tests pass on 2026-10-05: 28 bidirectional navigation paths
to eight landmarks and six stock locations, 31 actual ordinary `GameState`
arrivals across eight traversal fixtures, both bridge approaches, actual
roof/wall/rack cover with exposed-lane controls, and malformed mission,
severed entry and crushed headroom refusals. Traversal requires no jump and
preserves HP. `cargo fmt --all -- --check` and server all-target warning-denied
Clippy pass in the private two-job target. These are architectural checks, not
full workspace, complete client, rendering, enemy combat or fresh-player proof.

Retained failures preceded this pass: signed coordinate names violated the
identifier boundary; floating point authoring put a floor infinitesimally below
the permitted zero bound; the first crushed-ceiling negative control still left
enough room for the actual body. Authoring now writes valid identifiers and
millimetre coordinates, and the negative control actually removes body clearance.
The first PowerShell checker also rejected ordinary compiler stderr; its owning
process wrapper now retains a handle and reads the actual numeric cargo exit.
No acceptance threshold or movement rule was changed.

The next concrete work is the actual Remote Mine contract, Redactor, typed
mission and strict carry. No new gadget, enemy, wire, save promotion, runtime
presentation or renderer proof is claimed yet. The frozen M10 dependency remains
unchanged. This is one mission implementation plan, not a second project queue.
