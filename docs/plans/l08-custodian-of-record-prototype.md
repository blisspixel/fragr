# L08 Custodian of Record prototype

**Status:** in flight, 2026-10-02. Written before source work. The Proximity
Mine, the Auditor and their range land first; the archive level and its
presentation follow. The strict [M07-to-M08 carry](m07-m08-save-carry.md) is
implemented with actual mines and owned local continuation/retry checks, and
lands with the restored M07 through [PR #347](https://github.com/blisspixel/fragr/pull/347).
Fresh-player, full played quality and final art acceptance remain open.
**Spend:** $0. No paid generation, cloud or provider call. Existing textures,
the twenty-one Moon and offworld tiles, local GDScript rigs and bakes and the
existing audio library only.

## Goal

Build level 8, [Custodian of Record](../campaign/m05-custodian-of-record.md#level-8-design-twenty-level-expansion),
as a playable development prototype at least at M06's bar: the radial custody
archive around a central shaft, through the existing authoritative mission,
encounter, inventory, run and presentation seams. Introduce exactly one new
weapon and one new enemy, following the one-new-thing-per-level treatment in
[CAMPAIGN-MISSIONS.md](../CAMPAIGN-MISSIONS.md#level-8-custodian-of-record):

1. The **Proximity Mine**, found in a lower gallery equipment cage: it sticks,
   arms after a visible delay, blinks, then triggers on a body.
2. The **Auditor**, a human custody officer with a shield plate who channels a
   bounded repair into disabled Union bots.

Reach the level from Single Player > Practice and Development and
`--local-mission custodian_of_record`. Add M07 to M08 Continue Run after level
7's carry lands.

## Non-goals

- New movement verbs, moving lifts, general doors, vacuum, pressure or
  low-gravity rules. The freight car is a departure panel and presentation,
  not a ridden platform.
- Changes to existing weapon, enemy, difficulty or movement numbers. Campaign
  rules revision 3 stays; the Auditor rows are part of revision 3 from their
  first build, as the Heavy Sweeper and Turret rows were part of revision 2.
- A Remote Mine. The shared device record leaves room for its trigger policy;
  its detonator action and level 11 lesson stay unbuilt.
- Server-owned captive or Renn bodies. Captives, Renn and Orrin's cabinet are
  presenter figures driven by server facts; no NPC walking or arrival timing
  gates anything.
- Brief difficulty challenges (Severe: break every channel before a repair
  completes), par timing, the runner's line, fresh-player and difficulty
  acceptance. These stay open.
- Final art and audio. Clean placeholders route through the per-weapon,
  per-enemy and per-device tables so each final asset is a one-line swap.
- New narration or story images. Transitions use keyed text and the
  ScenePlayer text fallback.

## The Proximity Mine

A counted device, like the grenade, not a seventh gun slot. The readable
arsenal forbids a fake grenade gun slot, and level 7's Sniper Rifle is
extending the gun contract in parallel. The mine has its own count, its own
pickup, its own rebindable key and its own `place_mine` Action bit.

| Constant | Value |
|---|---:|
| Carry cap | 4, independent of grenades |
| Placement | rising-edge `place_mine`, 15-tick cooldown, one count per placement |
| Flight | 8 m/s along aim plus 2 m/s upward from the eye, existing gravity |
| Stick | first solid, floor or bound contact; holds position and surface normal |
| Arming | 40 ticks (2 s) after sticking, a steady lamp |
| Armed | blinks; trips when a body is within 2 m with clear sight |
| Trip delay | 4 ticks (0.2 s), a fast blink |
| Blast | 4.5 m radius, 130 raw damage, linear falloff, solid occlusion |
| Live cap | 3 per owner, 32 globally; a placement over the cap is refused and spends nothing |
| Flight bound | 100 ticks; an unstuck mine is removed without a blast |

Who trips it: the owner, and any living active body the owner's damage would
land on. A companion or teammate the owner cannot hurt never trips it. Blast
damage, armor, death, encounter hits and self damage use the grenade's shared
resolution; the owner can be hurt, never credited.

Cleanup: explicit leave, the owner's death, retry, party reset, round/map
replacement and departure clear owned mines. This differs from grenades on
purpose: a thrown grenade is committed, a placed mine is an owned device that
goes dark with its owner.

Records gain a separate `mines` column (attacks, damaging attacks, kills,
effective HP and armor), defaulted to zero and omitted when unused, beside the
grenade column. Record version 1 and the gun slots keep their meaning.

Saved equipment does not store a mine count in this increment: mines are found
in level 8 and no later mission exists to carry them into. Retry restores the
in-process entry count. The first later mission that carries mines versions the
run file.

## The Auditor

The campaign Auditor is an encounter `EnemyKind`, separate from the Episode 0
arcade "AUDITOR" rule-bot label, which stays an arcade prototype.

| | Auditor |
|---|---|
| Health, weapon | 120, Pistol (its own finite Bullets) |
| Gait | 0.4 of top speed |
| Attack, Assisted / Standard / Severe | windup 22 / 14 / 12, recovery 32 / 22 / 18 ticks, one shot |
| Hit reaction | unarmored: any damaging hit staggers it for 6 ticks |
| Shield plate | traced shots from within 60 degrees of its facing deal half damage; blasts wrap the plate |
| Repair channel, Assisted / Standard / Severe | 60 / 44 / 36 ticks |
| Channel start | a disabled Sweeper or Heavy Sweeper from its own group within 18 m and clear sight |
| Channel snaps | any damaging hit, broken sight to the body, or the body leaving |
| Repair result | the body stands at half its spawn health in a 20-tick recovery |
| Hard limit | two completed repairs per Auditor, never a third |

Repair restores a disabled bot body, never a person: Clerks and Auditors are
not repairable. The existing 40-tick disabled window holds; a channel in
progress keeps its body until the channel resolves. The Auditor faces the body
while channeling, so its plate faces away from a flank.

## Level shape

Map 1008, one static world plus two precomputed stages, half extent about 40 m.
A square-ringed archive around a central shaft visible from every floor:
ground (records hall), lower gallery at 3 m, upper gallery and machinery bridge
at 6 m, stairs walkable without a jump, and a cooling/service ring linking the
galleries.

| Beat | Space | Encounter | Notes |
|---|---|---|---|
| 1 | Entry checkpoint | none | Freight lane lights visible below the far bridge |
| 2 | Records hall, desks around the shaft | `records_hall`: Clerks and Sweepers | Galleries stacked overhead |
| 3 | Lower gallery | `lower_gallery`: local guards | Renn's registry desk after the clear (`custodian_joined`) |
| 4 | Lower gallery equipment cage and one-entrance alcove | `mine_lesson`: 2 Sweepers dispatched down a bent corridor | Mines in the cage; the corridor hides the alcove mouth until close |
| 5 | Upper gallery custody platforms | `upper_auditor`: 1 Auditor, 3 Sweepers | The onward seal lifts and the bays open when the Auditor falls |
| 6 | Service ring | optional `service_ring` | Orrin's cold cabinet (`recovered_mind_secured`), armor secret |
| 7 | Machinery bridge | `machine_bridge`: second Auditor and Sweepers below, Clerks on the far approach | Four support nodes; the machine drops down the shaft |
| 8 | Bridge desk | none | Transfer evidence; the uncalled car and *Authorized noise* panel |
| 9 | Converging gallery stairs to the freight lane | `exit_counter` | Mines on the stairs, then a fresh shared departure |

Frozen objective IDs, in order: `hall_cleared`, `lower_gallery_cleared`,
`mines_cleared`, `auditor_cleared`, `machine_wrecked`, `evidence_taken`,
`exit_cleared`, then `party_departed`. Arrival objectives bind to their required
groups as in M06. `machine_wrecked` is a Shoot objective naming the next intact
node. The departure is a fresh aimed Use with the living ready party inside the
freight boarding region.

The one door is the upper gallery seal: the onward exit stays shut while the
Auditor stands and opens when it falls, a one-way precomputed world change that
never closes on a body. The machine's fall is the second precomputed change.
Nodes take resolved ray impacts through the M03 registered-solid path, only
while the bridge fight is live.

Optional lower-bay release (`custody_released`) is a Use at the bay panel after
the Auditor falls. Captive figures walk out as presentation; the evacuated state
is recorded separately at departure. Three secrets follow the brief: cooling-loop
armor at the six pipe junction, the observation cage over the records hall
(Bullets in place of the unbuilt Repeater), and the lost-property cage (Shells, a
medkit and the jacket with the six).

## Architecture impact

Milestone B:

- `sim/mine.rs` beside `sim/grenade.rs`, sharing its swept contact and the
  explosion resolution refactored to take a radius and peak damage.
- `inventory.rs` mine count; `maps/authored/supplies.rs` `proximity_mine`
  grant; `PickupKind::ProximityMine`.
- `protocol.rs` Action `place_mine`, Snapshot `mines`; `protocol/explosive.rs`
  `MineState`; `protocol/loadout.rs` `proximity_mines`; `protocol/statistics.rs`
  `mines` column.
- `protocol/actors.rs` `EnemyKind::Auditor`, `EnemyPhase::Channeling`, optional
  `channel_target` and `repairs_left`; `encounters/enemy.rs` and `encounters.rs`
  own the channel, the hold on the disabled body and the repair; `sim.rs` applies
  the shield to traced damage.
- `inventory/controller.rs` retains explicit placements; agents prefer a
  channeling Auditor in sight.
- `server/maps/test/custody-range.json` (map 1014): the cage, the bent corridor,
  the alcove and an Auditor bay.
- Client: `mine_state.gd`, mine presentation in the grenade effects owner,
  `equipment_hud.gd` count, `place_mine` input, `actor_state.gd`,
  `enemy_view.gd` Auditor table entry, shield plate and channel beam,
  `player_record.gd` column.

Milestone C and D:

- `protocol/m08.rs`, `maps/authored/m08.rs`, `mission/m08.rs`,
  `mission/controller/m08.rs`, with bounded glue in their current owners,
  following M06 and M03. `MissionId::CustodianOfRecord`, map 1008.
- `local.rs`, `main.rs` and the client menu accept `custodian_of_record`.
- Client: `m08_mission_state.gd`, the `m08_archive.gd` presenter (records
  machinery, personal remnants, practical light, Renn, captives, Orrin's
  cabinet, the falling machine and the car), `m08_arrival` and `l08_l09` scene
  manifests, keyed world signs and a `client/qa/m08_custodian_of_record.json`
  route.

Milestone E: `mission/run_file.rs` promotes a completed M07 run into M08 with
no refill, retaining every earlier outcome, after level 7's carry lands.

## Protocol changes

Capability numbers follow `main` at merge time. Level 7 claims the next two for
the Sniper Rifle and M07; this track takes the following ones.

- Mine and Auditor capability: Action `place_mine`, loadout
  `proximity_mines`, pickup kind `proximity_mine`, snapshot `mines`, record
  `mines`, actor kind `auditor`, phase `channeling`, `channel_target`,
  `repairs_left`. Required only where a map places an Auditor or grants mines.
- M08 capability: the `m08` geometry and mission facts and the
  `custodian_of_record` mission id. Required only on M08.

`docs/protocol.md` and `agent-adapter/README.md` change in the same pull
requests, with tests on both sides.

## Verification

Milestone B, seeded and deterministic: stick on wall, floor and ceiling;
arming then blink; no trip while arming; proximity trip, trip delay and blast;
blocked blast behind a wall; owner damage without credit; live cap refusal
spending nothing; empty and capped inventory; cleanup on leave, death, retry and
reset; flight bound; companion non-trigger. Auditor: channel start conditions,
exact channel ticks per tier, snap on hit, on broken sight and on body removal,
two repairs and never a third, Clerks never repaired, half health on repair,
shield halving from the front and not the flank, blasts unshielded, range reset.
Wire strictness on server, adapter and client harnesses.

Milestone C and D: authored validation; shared-movement route proofs with
actual `GameState` players for every objective, supply, landmark and enemy in
all three stages; seeded full clears; retry and continue; node damage gating;
local child launch; an ordinary-input rendered tour through the whole level with
inspected stills. The full AGENTS.md verification list before each pull request.

## Spend gate

$0. No paid image, audio, model or cloud request runs on this track.

## Success criteria

- The Proximity Mine and the Auditor exist on the wire, validated by server,
  adapter and client, and play differently from the grenade and every earlier
  enemy.
- Arming, trip and channel windows are measured in ticks; every snap path and
  the repair limit are tested.
- Level 8 is playable start to finish through ordinary input, with an inspected
  rendered tour, seeded clears and honest captions.
- Fresh-player teaching, difficulty, pacing, par and final art and audio
  acceptance remain recorded as open.

## Progress

- Milestone A: plan merged in [PR #319](https://github.com/blisspixel/fragr/pull/319).
- Milestone B: the Proximity Mine, the Auditor, the custody range (map 1014),
  agent priority and client presentation merged in
  [PR #323](https://github.com/blisspixel/fragr/pull/323). Sabotage took
  capability 28 first and the Sniper Rifle 30, so the custody devices use 29
  and M08 uses 31.
- Milestones C and D: the archive (map 1008) with its three precomputed stages,
  mission facts, controller steering, local child, client state, presenter,
  HUD, menu entry, keyed pages and route manifest, in the level pull request.
- Milestone E: M07 to M08 carry waits for level 7's carry on `main`. Every
  saved-run reader refuses an M08 stage until then.

### Decisions taken without Nick

- The mine is a counted device with its own action and key, not a seventh gun
  slot, matching the readable arsenal and leaving the Sniper's slot alone.
- A placed mine goes dark when its owner dies; a thrown grenade does not.
- Renn, the captives and Orrin's cabinet are presenter figures driven by facts.
  The seal is the one door and only opens; it gates the onward route rather
  than closing behind the party.
- The early Repeater secret grants Bullets, since the Repeater is unbuilt.
- The arrival and departure pages are reader-paced keyed text, with no
  generated narration.
- Steel screens close the records hall's shaft on its north, west and east
  sides at floor level, so the opening fight arrives around the sides instead
  of five guards firing across the shaft at once. The south rail stays low for
  the view up the shaft.
- Ordered archive arrivals also count once the next fight wakes, the catch-up
  rule the other campaign levels gained on `main`.
- The optional `service_ring` group of beat 6 is two Clerks among the cooling
  pipes and a Sweeper from the bridge end. It wakes as the party steps through
  the lifted seal, binds no objective and never gates departure.
- The cage's four mines cover two placements: one down the corridor the post
  pair walks up, one at the alcove mouth.
- Armor on the east tower landing before the Auditor fight, and Bullets by the
  west records desk on the way to the stair.

### Fun check (direction of 2026-10-03)

Measured by `m08_pacing_first_contact_and_longest_quiet_walk` with shared
movement at full running speed on the tour route. A quiet walk is time with no
fight, no supply claimed and no reveal, rescue, secret or broken node.

| Rule | State |
|---|---|
| Teach by fighting | First contact 3.7 s from spawn past the entry Rifle. Longest main-route quiet walk 9.4 s. The one breath is the 15.9 s walk back to the bridge desk after the machine falls; the optional bays add a 17.0 s return that ends in the pipe ambush. |
| Different shapes, never two alike in a row | Hall: desk crossfire, then a flank push around the screened shaft. Lower gallery: stair-head ambush. Mine lesson: a trap sprung on a converging pair. Upper gallery: Auditor repair fight. Service ring: close pipe ambush. Bridge: vertical crossfire with the second Auditor in the well. Exit: converging push up both freight stairs. |
| Weapon choice | Hall distances suit the Rifle; the stair head and the pipes are close enough for the Shotgun; mines for the post and the exit stairs; flanking or blasts beat the Auditor's plate; the Railgun reaches into the well. Fresh-player play has not confirmed the swaps. |
| Mine lesson as a trap | Picking up the cage dispatches the pair; one mine down the corridor and one at the mouth take both when the post never sees the player (`m08_post_pair_walks_into_the_corridor_mines`). Partly met: a post that sees the player and loses the alarm walks home instead of pushing on. |
| Doom surprises, sparingly | The cage pickup springs the post. The pipe ambush waits on the way back from the optional bays. |
| Secrets | Three, each marked with the six. Their contents follow the campaign brief (Bullets, Shells and a medkit, armor), so the early reward is supply, not new power. |
| Rescue and evidence never block | Bays and cabinet are optional; the evidence arrival also counts once the counterattack wakes; no rescue can fail. |
| One climax | Four glowing nodes shot apart until the custody machine drops through every gallery, then the counterattack up both freight stairs to an uncalled car. |

### Evidence

| Check | Result |
|---|---|
| Focused server tests: mine, Auditor, range, M08 stages, nodes, full clear, retry, authoring, controller, route walk, pacing, mine trap in the archive | pass |
| Local M08 child launch with capability admission | pass |
| Client harnesses `test_custody_devices`, `test_m08_mission` and the touched shared harnesses | pass |
| Full Godot check on the milestone B tree | `Godot checks: PASS` |
| First range tour | exposed a post too close for the mine to arm; moved farther |
| Second range and archive tours | range stuck leaving the alcove; archive hall fight shot across the open shaft from every side; both fixed |
| Third archive tour | the lesson mine landed inside the alcove, the post stopped short and the player later walked onto its own live mine; both mines now go into the corridor |
| Fourth to seventh archive tours (2026-10-03) | ordinary input passes the checkpoint, both secrets on the way, the hall, the lower gallery, the registry, the cage and the corridor mine throw. One post Sweeper walks into the mine every time; the other never comes into view of the alcove, and neither the corner, the mouth search nor a hunting approach toward its post confirmed it within the 25 s combat window. The tour now throws one corridor mine and hunts the survivor, then counts the lesson when the upper gallery wakes. |
| Local gates (2026-10-03) | fmt, clippy, workspace tests, bench, coverage 93.77 % lines, release build, deny, the eight playtest smokes, roster and soak all pass |
| Full Godot check | one stale selector expectation (five development missions) fixed to six; every other harness passes |

### Handoff

- What works: the archive plays end to end on the server. The seeded full
  clear, ordered arrivals with catch-up, seal, nodes, machine drop, departure,
  retry, the corridor mine trap and the route walk with pacing are all proven
  with actual `GameState` players and shared movement.
- What is left: a clean rendered ordinary-input tour of the whole route. The
  latest runs pass every state through the corridor mine throw and its live
  blink; the mine cleanup fails because the second post Sweeper does not follow
  its partner into the alcove corridor in rendered play. A server probe shows
  why: a post that sees the player and then loses the alarm walks home to its
  post on the lower gallery east side, which is reachable and on the onward
  route, so the level stays completable, but the trap only catches a post that
  never saw the player. Decide whether a dispatched post should keep pushing to
  the alcove, then pass the remaining states (Auditor, service ring ambush,
  bridge, nodes, evidence, exit fight, departure) and inspect their stills. The
  custody range tour's audit-bay combat also needs a clean rerun.
- Next steps: rerun `client/qa/m08_custodian_of_record.json` and
  `client/qa/custody-range.json` under the render lock, adjust waypoints from
  the inspected stills, publish an `m08_*` gallery, then M07 to M08 carry once
  level 7's carry lands. Fresh-player and difficulty acceptance stay open.
