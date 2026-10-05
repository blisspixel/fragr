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

The initial remote prototype uses an independent carry cap of six, four live
charges per owner and 32 globally, with the existing 15-tick placement admission.
After real swept surface contact, arming is 40 ticks. A fresh trigger starts a
four-tick visible detonation commitment on every currently armed owned charge;
flying and still-arming charges are not silently queued. Holding the trigger
does not detonate a later-armed charge. The shared 4.5 m, 130 peak covered mine
blast is the initial bounded balance, subject to played acceptance. Every
admitted placement owns one attack record; resolved damage is never credited to
a proximity-mine column. Device death/leave/reset cleanup follows owned mines,
not committed grenades. These are prototype constants, not a balance claim.

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

The independent Remote Mine state boundary now validates flying, arming, armed
and deliberately triggered phases in native code and the existing client
custody-device harness. Eighteen shared valid and malformed vectors agree;
three owning native tests, the focused client harness and warning-denied server
Clippy pass. The first client import used an invalid relative log path and is
retained as a failed setup; the absolute-path import and focused harness are
clean. These types are not yet delivered in snapshots or admitted through input,
and no inventory, flight, blast, save carry or live device is claimed.

The next source component implements actual swept sticking flight, exact
arming, owner-specific multi-charge commitment and one terminal detonation
outcome. It extracts the existing mine flight without changing contact rules.
Early commands are refused without later queuing, invalid clocks reject a whole
multi-charge command, and invalid contact transitions leave the original state
intact. The component remains outside live `GameState` admission and blast
resolution until finite inventory, records and carry are wired together. No
owner lifecycle, gunfire integration, live equipment delivery or played proof
is inferred from these component checks.

Six owning component tests now pass, alongside all ten existing mine tests and
the broader simulation selection: 45 passed, one retained ignored capture.
The tests cover real wall/floor/ceiling sticking, exact 40-tick arming and
four-tick commitment, no early-command queue, owner isolation, a single terminal
outcome, bounded flight, bad clocks and deltas, atomic deadline overflow and
hitch displacement clamping. Formatter and server all-target warning-denied
Clippy pass on the final source. One preceding lint failure in the extracted
contact-coordinate loop was corrected with an equivalent iterator; its receipt
is retained, with no lint suppression or altered contact tolerance.

The next stock component adds the independent six-count inventory and current
private loadout boundary, with zero omitted. The reserved version 14 save
boundary uses an exact version 13 decoder and strict pre-remote equipment
conversion for earlier documents. Valid historical counts become zero only
after their original shape passes; even a forged zero remote field is rejected.
The current earlier mission stages still refuse nonzero Remote Mine carry.
This source work does not grant Right of Search, a remote-control input or any
new device in a player's world. Actual admission, blast records and the complete
M11 promotion remain required before this leaf can be accepted.

The stock checkpoint passes 15 focused remote tests and all 66 owning run-file
tests, including existing M01-M10 transitions, retries, crew contacts and
historical archives. The existing client equipment harness passes with distinct
six-charge/four-proximity counts and malformed-value controls. The version 13
upgrade retains actual M09/M10 crew history and exact source bytes through an
interrupted write, successful archive and reopen. This is source and headless
evidence. The changed current-version expectations in the M10 local client
harness still require a fresh matching native and full composed checker; no
packaged or played save-version acceptance is claimed at this checkpoint.

The next concrete work is the actual Remote Mine integration, Redactor and
typed mission. No live gadget, new enemy, playable save promotion, runtime
presentation or renderer proof is claimed yet. This is one mission
implementation plan, not a second project queue.

The stock source then passes the full locked workspace suite, including 978
server unit tests (three existing ignored captures) and all 18 local-process
tests. The first workspace run exposed four local-process assertions that still
expected the current writer to produce version 13. Those assertions now expect
14 while preserving every promotion, outcome and finite-equipment check. Two
brain fixtures also explicitly initialize the new remote count to zero; decision
behavior is unchanged. The failed first receipt and successful second receipt
are retained separately. These checks do not replace the pending matching
complete client, capability, live device, mission or renderer gates.
