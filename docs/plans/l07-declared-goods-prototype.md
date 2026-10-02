# L07 Declared Goods prototype

**Status:** in flight, 2026-10-02. Written before source work. Milestone B
(Sniper Rifle, Ranged Sweeper and their range) lands first; the level, run
carry, entry and presentation follow in a second pull request.
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
  sounds. This track routes clean placeholders from existing assets through the
  same per-weapon and per-enemy tables so each swap is one line.
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
  capability 28. Arcade and earlier authored missions keep their requirements.
- `server/maps/test/sniper-range.json` (map 1013): a rack, finite Cells, a firing
  step behind a sill, a far rim platform with one Ranged Sweeper, and a walking
  flank.
- Client: `equipment_state.gd` (weapon, Cells pool, display name, key 6),
  `player_record.gd` (seven columns), `shot_effects.gd` (tracer instead of
  beam), `actor_state.gd` (kind), `enemy_view.gd` (one texture table entry),
  a scope overlay and zoom bound to the right mouse button, a glint billboard
  during the Ranged Sweeper windup, and audio table entries. The placeholder
  Ranged Sweeper atlas comes from a local rig and bake on the Sweeper chassis.

Milestone C to E:

- `protocol/m07.rs`, `maps/authored/m07.rs`, `mission/m07.rs`,
  `mission/controller/m07.rs`, with bounded glue in their current owners,
  following M06. `MissionId::DeclaredGoods`, map 1007, capability 29.
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

- Capability 28: the `sniper` weapon id in loadouts, shot traces, pickups,
  actions and records, and the `ranged_sweeper` actor kind. Required only where
  the map contains either.
- Capability 29: the `m07` geometry and mission fact envelopes and the
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
  overlay and the placeholder atlas outlines.

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
