# L07 Declared Goods prototype

**Status:** in flight, 2026-10-03. Written before source work. Milestone B
(Sniper Rifle, Ranged Sweeper and their range) is on main. The restored level,
run carry, entry and presentation are under full route verification.
**Spend:** $0. No paid generation, cloud or provider call. Existing textures,
the existing audio library, local GDScript rigs and bakes only.

## Goal

Build level 7, [Declared Goods](../campaign/l07-declared-goods.md), as a
playable development prototype at least at M06's bar: the lunar curfew town,
the crater cut and the depot freight approach, through the existing
authoritative mission, encounter, inventory, run and presentation seams.
Introduce exactly one new weapon and one new enemy, following the
one-new-thing-per-level treatment in [CAMPAIGN-MISSIONS.md](../CAMPAIGN-MISSIONS.md):

1. The **Sniper Rifle**, found in the curfew post's rack, fed by Cells, with a
   scope that is presentation only.
2. The **Ranged Sweeper**, a Union marksman bot with a distinct antenna
   silhouette that glints, holds and then fires one precision shot.

Promote a completed M06 run into M07 with no refill, retaining every earlier
outcome. Add Continue Run and Practice entry, agent controller support, an
ordinary-input rendered tour and inspected stills.

## Non-goals

- New movement verbs. There is no crouch; the roof window's sill is ducked by
  stepping off a supported firing step.
- New global mechanics: no noise model, no beam-sighting alarm, no vacuum,
  pressure or low-gravity rules, no moving lifts or doors. The level has zero
  doors.
- Changes to existing weapon, enemy, difficulty or movement numbers. Campaign
  rules revision 3 stays; the new rows are part of revision 3 from their first
  build, as the Heavy Sweeper and Turret rows were part of revision 2.
- Final art and audio. The parallel art and sound tracks supply the Sniper
  Rifle, scope, Ranged Sweeper art and the sniper, tell and curfew chime
  sounds. This track routed clean placeholders through the same per-weapon and
  per-enemy tables, then wires the delivered files in their place.
- Brief difficulty challenges (cross without losing armor, kill every rim
  Ranged Sweeper before it fires) as server facts, the runner's line timing,
  par, fresh-player and difficulty acceptance. These stay open.
- New narration or story images. Story transitions use existing keyed text and
  the ScenePlayer text fallback.

## Design decision: why the Sniper Rifle exists beside the Railgun

Both are Cells-fed long guns, one level apart. The accepted arsenal contract
fixes the Sniper as the existing hitscan path with a tighter cone, a slower
cooldown and higher damage than the Rifle, and forbids reusing Rail damage or
the rail beam. Within that contract the two guns own different distances:

| | Railgun (unchanged) | Sniper Rifle |
|---|---|---|
| Damage per hit | 80 | 70 |
| Cooldown | 20 ticks (1.0 s) | 32 ticks (1.6 s) |
| Cone half-angle | 0.012 rad (0.69 degrees) | 0.004 rad (0.23 degrees) |
| Reach | 60 m | 90 m |
| Ammunition | 1 Cell per shot | 1 Cell per shot |
| Pickup grants | 10 Cells | 8 Cells |
| Shot presentation | bright beam from muzzle to impact for 0.14 s | no beam; a faint thin tracer near the impact |
| Viewing | none | scope zoom while held, a sprite overlay |

**The Railgun is the mid-range power gun.** It fires faster and hits harder:
one Rail hit drops an 80 HP Sweeper, the Sniper needs two. Inside about 42 m
its cone still lands on a centred body; beyond that its spread starts to miss,
and beyond 60 m it reaches nothing.

**The Sniper Rifle is the far precision gun.** Its cone stays inside a body's
0.5 m radius out to its 90 m reach, so a steady aimed shot lands where the
scope points. It is slow, so it loses a close trade, and its 70 damage is tuned
to the 70 HP Ranged Sweeper: one aimed shot answers one marksman.

The distinction is testable: a 75 m Rail shot resolves as out of range while a
Sniper shot hits; at 55 m a seeded Rail volley misses a centred body sometimes
while the Sniper never does; a Sweeper takes one Rail hit or two Sniper hits;
the Sniper's trace carries its own weapon id, 70 damage and 32-tick cadence.

**Does the Railgun's beam reveal the shooter?** Visually, yes: every viewer sees
the bright line back to the muzzle. The Sniper draws only a short fading streak
at the far end that does not point back. Server alarm stays identical for both
weapons (a hit wakes the struck guard's group, as today), because a beam or
noise alarm would be a new mechanic. Sound and recoil also differ: the Sniper
keeps a heavier, slower kick and a separate fire sound table entry.

## The Ranged Sweeper and its tell

A Union marksman bot on the Sweeper chassis with a tall rear antenna mast and
a long scoped rifle. It never walks: it holds its platform, which keeps the
duel bounded and readable.

| | Ranged Sweeper |
|---|---|
| Health, weapon | 70, Sniper Rifle (70 per hit, its own 8 Cells) |
| Gait | none, it holds its post |
| Sight and engagement | 90 m line of sight; notices a new target only within 1.0 rad of its authored facing |
| Windup (glint and hold), Assisted / Standard / Severe | 40 / 30 / 24 ticks (2.0 / 1.5 / 1.2 s) |
| Recovery, Assisted / Standard / Severe | 50 / 40 / 32 ticks |
| Attack | one shot, aim locked when the glint starts |
| Hit reaction | unarmored: any hit staggers it for 6 ticks and cancels the windup |
| Losing sight | cancels the windup (shared rule): 12-tick recovery, no shot |

**Visibility.** It sees a participant when either the body centre or the eye
is in clear line of sight, and aims at the centre when visible, otherwise at
the head. Peeking over a sill therefore counts as being seen; dropping fully
below it does not. Existing enemies keep their centre rule.

**Reaction window.** The glint starts on the first windup tick (the snapshot
phase becomes `windup` with `phase_ends` set). The shot resolves on the tick
`phase_ends`. A participant who breaks sight before the controller's decision
on that tick cancels the shot; on Standard that is 30 ticks (1.5 s) from the
first visible glint. Tests measure the exact ticks for every tier. Severe stays
above one second.

**Placement rule.** A Ranged Sweeper needs a readable platform, cover within a
few steps of the player's line, and a flank or shotgun approach. Never an
unavoidable gauntlet.

## Level shape

Map 1007, a static world, half extent at most 72 m. Town floor at ground level
under a ballistic glass pressure dome; the crater cut is a raised trench beyond
the town's north wall; the depot rim stands at the far end. The depot's radial
tower is visible through the dome from the tunnel onward.

| Beat | Space | Encounter | Notes |
|---|---|---|---|
| 1 | Transit tunnel arrival, habitation ring under the dome | none | Shutters down, dark windows, curfew chime cue |
| 2 | Ring street, market stalls and stair wells | `curfew_patrol`: 3 Clerks, 2 Sweepers | Close to middle distance |
| 3 | Market vault plaza | `vault_plaza`: 2 Notaries at dome height, 3 Clerks behind barriers | Notary hover bands validated |
| 4 | Side street window | none | The silent window figure taps and points |
| 5 | Curfew post square | `curfew_post`: 4 Clerks, 1 Turret over the gate | Clearing it lights the lamps toward the cut |
| 6 | Post rack and roof window | `rim_lesson`: 1 Ranged Sweeper across the cut | Sniper Rifle rack, firing step and sill |
| 7 | Climb to the overlook | none | View back over the port |
| 8 | Crater cut | `crater_cut`: 5 Ranged Sweepers on rim platforms, 4 Sweepers between berms | Shotgun close, Sniper far |
| 9 | Depot freight approach | none | Fresh shared departure |

Frozen objective IDs, in order: `ring_cleared`, `plaza_cleared`,
`post_cleared`, `window_cleared`, `cut_cleared`, then `party_departed`. Each of
the first five is an Arrival bound to its required group. The departure is a
fresh aimed Use with the living ready party inside the freight boarding region,
after `crater_cut` clears. There is no optional branch. Three secrets follow the
brief: the stall-roof tool cache above the vault, the chalk 67 alley panel, and
the berm-top ledge reached by a readable jump from the second shield wall.

Twenty-five required guards. Supplies are finite and personal or contested as
in M06. The rack grants the Sniper Rifle and its 8 Cells, with separate finite
Cells before the window and the cut; Rifle, Shotgun and Railgun routes stay
usable. The cut keeps berms between rim platforms so a participant on the
ordinary route is seen by at most two marksmen at once; tests count those
sightlines from route points.

## Architecture impact

Milestone B:

- `protocol.rs`: `WeaponType::Sniper` (`sniper` on the wire, name `Sniper`)
  with the table above. `protocol/loadout.rs` appends it at index 6, Cells pool,
  8 pickup Cells; it is not in the arcade arsenal.
- `protocol/statistics.rs`: records keep version 1 and serialize the shortest
  prefix of five, six or seven gun columns that holds every non-zero count.
- `protocol/actors.rs`: `EnemyKind::RangedSweeper` (`ranged_sweeper`).
  `encounters/enemy.rs` adds its body, timing, visibility and a stationary
  marksman controller beside the Turret and Jammer branches.
- `inventory/controller.rs`: agents swap to a usable Sniper when the nearest
  hostile is beyond the held weapon's reach and inside the Sniper's.
- `run.rs`: maps that place a Ranged Sweeper or grant a Sniper require
  capability 30. Arcade and earlier authored missions keep their requirements.
- `server/maps/test/sniper-range.json` (map 1013): a rack, finite Cells, a firing
  step behind a sill, a far rim platform with one Ranged Sweeper, and a walking
  flank.
- Client: `equipment_state.gd` (weapon, Cells pool, display name, key 6),
  `player_record.gd` (seven columns), `shot_effects.gd` (tracer instead of
  beam), `actor_state.gd` (kind), `enemy_view.gd` (one texture table entry),
  a scope overlay and zoom bound to the right mouse button, a glint billboard
  during the Ranged Sweeper windup, and audio table entries. The Ranged
  Sweeper atlas comes from the art pass's local rig and bake on the Sweeper
  chassis.

Milestone C to E:

- `protocol/m07.rs`, `maps/authored/m07.rs`, `mission/m07.rs`,
  `mission/controller/m07.rs`, with bounded glue in their current owners,
  following M06. `MissionId::DeclaredGoods`, map 1007, capability 31.
- `mission/run_file.rs`: run file version 8 represents playable M07, the
  Sniper in carried equipment, retained M06 outcomes and the pending
  `custodian_of_record` edge. A strict v7 reader upgrades validated v7 bytes
  with an exact archive; historical shapes reject a Sniper they could never
  contain. The completed M06 edge promotes into M07 under the existing writer
  lock with no refill, because Episode II was already refilled.
- `local.rs`, `main.rs` and the store accept `declared_goods`.
- Client: `m07_mission_state.gd`, the `m07_town.gd` presenter (dark shutters,
  the lamp sequence driven by the `post_cleared` fact, a chime cue point, the
  silent window figure and the depot tower), menu entries, story pages and a
  `client/qa/m07_declared_goods.json` route.

## Protocol changes

- Capability 30 (Sabotage took 28 and the level 8 devices 29 first): the
  `sniper` weapon id in loadouts, shot traces, pickups, actions and records,
  and the `ranged_sweeper` actor kind. Required only where the map contains
  either.
- Capability 31: the `m07` geometry and mission fact envelopes and the
  `declared_goods` mission id. Required only on M07.
- No new action. The scope is client presentation; aim and fire are unchanged.

`docs/protocol.md` and `agent-adapter/README.md` change in the same pull
requests, with tests on both sides.

## Verification

Milestone B, seeded and deterministic:

- A tight Sniper hit at long range; a miss when the aim is outside the cone;
  no Rail damage and no rail weapon in the trace; a Rail shot beyond 60 m
  reaches nothing while the Sniper hits; seeded cone comparison at 55 m.
- Cells: one per shot, dry fire with none, pickup amounts, cadence.
- Ranged Sweeper: no shot before the documented windup on every tier, the
  shot on its final tick, broken sight cancels with a 12-tick recovery, a hit
  staggers and cancels, the notice cone, eye-only visibility and head aim, and
  party-wipe reset on the range.
- Wire strictness on both sides, records with seven columns and their older
  five and six column shapes, capability admission for the range.
- Client harnesses for equipment, records, shot effects, actor kinds, the scope
  overlay, the marksman cue and the atlas outlines.

Milestone C to E:

- Authored validation, shared-movement route proofs with actual `GameState`
  players for every objective, supply, landmark and enemy, rim sightline counts,
  seeded clears of the full route, retry and continue, store tests for v7
  upgrade, M06 to M07 promotion without refill and outcome retention, and real
  local child launch.
- The ordinary-input rendered tour through the whole level, with inspected
  stills of arrival, the plaza fight, the post set piece, the lamps, the Sniper
  lesson, the crater duel and departure.
- The full AGENTS.md verification list before each pull request.

## Spend gate

$0. No paid image, audio, model or cloud request runs on this track.

## Success criteria

- The Sniper Rifle and Ranged Sweeper exist on the wire, validated by server,
  adapter and client, and play differently from the Railgun and the Turret.
- The tell window is measured in ticks on every tier and broken sight cancels.
- Level 7 is playable start to finish through ordinary input, with an inspected
  rendered tour, seeded clears and honest captions.
- A completed M06 run continues into M07 without refill and keeps its outcomes.
- Fresh-player teaching, difficulty, pacing, par and final art and audio
  acceptance remain recorded as open.

## Progress

Plan written before source work.

### Milestone B, 2026-10-02

The Sniper Rifle, Ranged Sweeper, capability 30, seven-column records, agent
Sniper selection and the development range are implemented. After the art
pass (#321) the Sniper's first-person frames, pickup and scope plate come
from `WeaponArt`, the marksman atlas and its harness from the art rig, and the
Sniper tracer turns orange to match its flash. The Sniper report and glint
tone remained placeholders until the sound pass (#322) wired its delivered
cues. Seeded server tests cover the tight hit, the out-of-cone miss,
Rail reach and cone at 55 m, cadence, dry fire, the tell on every tier, sill
cancellation, head visibility, hit interruption, the notice cone and range
admission. Local gates pass workspace tests, warning-denied Clippy, 94.32
percent unfiltered line coverage, the benchmark, dependency policy, every
playtest smoke, the roster and the soak.

The ordinary-input range tour passed five states. Its recorded cancellation
holds a clear windup at tick 922, the step off the firing step, a blocked
windup at 925 and a 12 tick recovery at 926, with no shot through the
original deadline 952. Inspection of the scoped captures found one defect: a
marksman shot landing on the viewer drew its tracer through the scope. Shots
that land within three metres of the viewer now draw no streak, with a
harness check. The first whole-client check failed one stale six-column
grenade record assertion, since corrected.

### Milestone B landed

PR #324 put the Sniper Rifle, the Ranged Sweeper, their range and the art
pass's delivered frames, pickup, scope plate and marksman atlas on main. The
capability is 30: Sabotage (#325) took 28 and the level 8 devices (#323) took
29 before it merged.

### Handoff, 2026-10-03

The session closed before level 7 itself was verified end to end, so the level
is not on main. Nothing on main is half-wired: main has milestone B only.

**Where the level work is.** Two git bundles hold it:

- `C:\GitHub\_backups\l07-20261003-level.bundle`: branch `feat/l07-level`,
  six commits on top of `de38e7d` (the #324 merge). Restore with
  `git fetch <bundle> feat/l07-level:feat/l07-level`, then rebase onto main.
- `C:\GitHub\_backups\l07-20261003-sound-wiring-reference.bundle`: branch
  `trial/l07-int`, an earlier reference merge of milestone B with the art and
  sound branches. The sound pass (#322) has since wired the Sniper report,
  scope cues, marksman glint and shot and the curfew chime constant on main
  itself, so this bundle is only a reference; the old placeholder sounds and
  their bake tool are retired from main with this handoff.

**What works on `feat/l07-level`.** Map 1007 (`server/maps/m07_declared_goods.json`,
generated from a scratch script not kept; edit the JSON directly) passes
authored validation: 146 solids, 25 required guards in five ordered groups,
zero doors, three marked secrets (a Railgun on the vault roof, Bullets in the
chalk 67 alley, Cells on the berm ledge). M07 protocol (`protocol/m07.rs`,
capability 31 on that branch, renumber to the next free number at merge),
mission progress with the shared arrival catch-up, the agent controller, run
file version 8 (M06 to M07 promotion with no refill, every earlier outcome
kept, version 7 upgrade with exact bytes archived, `custodian_of_record` saved
as the unbuilt next mission), local launch, Continue Run and Practice entries,
the town presenter (`m07_town.gd`: shutters, awnings, the window figure who
taps and points, the 30 second curfew chime with its PA line, the lamp line
after the post, the dome, the port behind and a 140 metre depot tower visible
from the tunnel mouth), the HUD line and prompt, world text, two story pages
built from existing keyed text, and docs (protocol, adapter README, AGENTS
seam row, maps README, roadmap, README and changelog). Verified there:
fmt, warning-denied Clippy and `cargo test --workspace --locked` pass (the
last map tuning touched only data, and the 12 M07 server tests were rerun
after it). Those tests cover ordered groups, the arrival gate and catch-up,
the window sightline and Rail reach, a seeded rack-to-step Sniper clear, cover
stops seen by no marksman, a crossing never watched by more than two
marksmen, tour walkability, the departure gate, Latch's restraint, the
controller and capability admission, plus three version 8 store tests. Client
harnesses `test_m07_local`, `test_m06_local` and `test_m05_local` pass;
`test_m07_mission` passed except its curfew chime check, which needed the
sound pass's `l07/curfew_chime.wav`, now on main.

**What is left.**

1. Rebase `feat/l07-level` on main and renumber the M07 capability. Its
   `l07_assets.gd` adds `CURFEW_CHIME_SOUND`, which main now defines; keep
   main's table. `test_m07_mission`'s chime check then passes.
2. Finish the rendered tour (`client/qa/m07_declared_goods.json`). Its first
   three stills (tunnel arrival, the depot tower from the tunnel mouth, the
   ring supplies) render correctly; the patrol fight does not yet complete
   inside the 25 second combat window after the Shotgun pickup wakes the
   patrol, because the Clerks hold their porches instead of closing. Tune the
   patrol's starting positions or the tour's search route, then iterate state
   by state to the freight departure and inspect every still.
3. Run `tools/godot_check.sh` and `tools/test_godot_check.sh` on the branch,
   then open the level pull request.

**Fun checks against the design direction.** Encounter shapes alternate:
patrol skirmish, plaza crossfire under the Notaries, the post assault with the
gate Turret, the window sniper duel, then the crater push. Taking the Shotgun
wakes the patrol a few seconds from the tunnel (pickup ambush); two cut
Sweepers come in behind from the end bays while the rim marksmen pin the
participant (revealed behind); the vault roof secret gives early power. From
route lengths at the 5 m/s top speed, first contact is about 3 seconds after
leaving the tunnel and the longest quiet stretch is the deliberate window
breath beat, about 13 seconds, with the overlook climb next at about 11
seconds. These are estimates from route geometry, not a measured play
session. Whether the crater climax is the moment people talk about needs
human play.

### Restoration on current source, 2026-10-03

The retained level bundle is reconciled with the current archive mission,
living-body contact, character art and strict historical save readers. M07
uses capability 32; M08 retains 31 and campaign rules remain revision 3.
Version 8 explicitly upgrades historical version 7 documents, archives their
exact bytes, and promotes completed M06 into M07 without an episode refill.
Both static mission envelopes remain separate. An absent envelope is omitted
on earlier maps rather than emitted as null.

The opening patrol now places its porch Clerk on the supported ground lane.
A server regression walks an actual participant through the ordinary supply
pickups, confirms that finding the Shotgun selects it, reselects the Rifle,
and clears all three Clerks while alive in the 25 second street window.
Each confirmed death comes from a resolved shot. The rendered route splits
the Shotgun pickup from Rifle selection for the same reason. Its revised
street capture clears those Clerks with 80 HP remaining. A later pass also
confirms a participant Shotgun kill on the first Sweeper, then records the
second Sweeper killing that participant during the ordinary search walk.
The patrol and full route acceptance remain open.

The route refinement exposes the existing target selector's distance
bound as an optional, validated `engagement_distance` in the combat capture
manifest. M07 Shotgun states use 10 metres so a visible distant guard does not
stop ordinary search-route walking. Other captures keep the current unlimited
selector by default. Boundary tests reject malformed distances and prove
that a distant visible guard is excluded until actual movement brings it into
the requested band. Short-range search reuses the existing no-fire approach
defense against committed tells. A harness proves that defense and preserves
the default search behavior. Capture diagnostics explicitly retain participant
death even if the development mission resets the pawn. These changes affect
capture inputs only; server reach, damage,
enemy intent and the 25 second combat window remain authoritative.

Focused server and store checks pass 16 tests, including M06, Sniper and M08
reader refusal on M07. Warning-denied workspace Clippy passes. The M07 client
boundary, real owned child launch, version 7 preview and M06 transition
harnesses pass. The menu harness now covers the M07 saved continuation and
its separate practice entry while retaining the pending M08 carry boundary.
The first full client pass exposed the absent-envelope serialization defect
and stale menu, story, archive capability and presenter-owned decoration
expectations. All were corrected. The complete fresh client gate passes import,
all 224 scripts and all 103 harnesses. The latest complete workspace tests pass,
including 864 server tests with three ignored tests. The focused distance and
search-defense harness passes after its final edits.

The whole rendered route, upper-room enclosure inspection, fresh-player
teaching, difficulty, pacing, par and final art and audio acceptance remain
open. M08 is available as a separate development mission; durable M07 to M08
carry remains the next bounded change after M07 route acceptance.
