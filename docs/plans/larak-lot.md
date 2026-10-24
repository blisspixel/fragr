# Plan: Larak Lot replaces the Arena Duel field on map 1

**Status:** implemented on `feat/larak-lot` (2026-10-23), not merged. Human
play, the live tour publish and the per-pad Plate kind remain open (see
[Open](#open)).
**Spend:** $0. Retained assets and local construction only; no paid generation.

## Goal

Nick, 2026-10-23: the multiplayer level we keep testing (Arena Duel, a flat
field of repeated crates) is boring; "surely we can do better". Map 1 becomes
**Larak Lot**, "a parking structure where the league settles debts": the FFA
and Duel home for 2 to 8 fighters, with loops and no dead ends, asymmetric
named quarters, one landmark seen from most of the map, height through decks,
stairs and a bridge, and item control built around one power item and one
power weapon in opposite corners and heights.

The design is the merged D3 spec (Pit, Stands, Bridge, Gallery) with grafts
from two other proposals, kept with its measured box model in
`.agents/larak-lot-20261023/` (ignored scratch). This file records what was
built and what was measured.

## Non-goals

- New collision kinds. Every stair is a run of 2 m treads with a 0.5 m rise;
  there is no sloped collision.
- The `PickupKind::Plate` item (cap 150, decaying above 100), the Tack and
  Fists spawn kit and Overtime. The Plate ships as an armour pad on its own
  clock until those land.
- Capture the flag on map 1. Larak Lot has no two-base route; the night
  playlist's CTF slot moved to Sector 9 and Directive 17.
- Paid assets. Wishes for the next asset round are listed below.

## Architecture impact

- `server/src/maps/larak_lot.rs` builds solids and their `MapSurface` kits in
  one order (the `low_water.rs` pattern), with pads, phase-one decorations and
  a twelve-slot spawn table. `build(MapKind::ArenaDuel)` points at it;
  `RuntimeMap::presentation_ref` and `spawn_slots` return its presentation and
  twelve. `MapKind::ArenaDuel` keeps its enum, index and wire id 1; the
  display name is "Larak Lot" (aliases `larak`, `lot`, `larak-lot`; `arena`
  and `duel` still parse).
- `ArenaPickup.clock` is an optional per-pad respawn clock. A pad with a clock
  keeps it in team modes too. Larak sets every pad: Plate 35 s, Rail 25 s,
  Bridge armour 25 s, the rest 15 s.
- `maps::validate` and `maps::unreachable` read an explicit spawn table when a
  map has one, and the flood fill is layered: a cell keeps every floor it is
  reached at, so the Pit under the Bridge and the Bridge itself both count.
- `sim/spawn.rs`: an opponent within 12 m counts as a threat even without a
  lane, and when every fixed bay is occupied the bounded nearby search runs
  instead of stacking bodies (twelve slots, up to sixteen fighters).
- `ctf_stands(ArenaDuel)` is `None`.
- Client: `LarakLot` (`client/scripts/larak_lot.gd`) is the venue presenter
  selected by `venue_for` ("larak lot" to `larak_lot`); `ArenaSky.larak_lot()`
  is the sky and light preset; `ArenaMaterials` and `EnvironmentTextures` map
  the six surface kits to retained textures; `ArenaBackdrop._build_lot` is the
  city outside the walls. The presenter adds no collision and redraws only the
  boxes it replaces, inside their own volumes.
- Benchmark: `BenchmarkCamera.SCENE_REVISION` is 2 (Larak Lot orbit, 31 m out,
  17 m up) and the JSON report records it. Revision 1 scores, recorded on the
  Arena Duel field, are not comparable.
- Playtest reports gain `pickups_by_pad`.

## Protocol or API changes

No new message or field. `map_name` for map 1 is "Larak Lot",
`PLAYLIST_NAME` follows it, and MapInfo for map 1 now carries a
`presentation` block (surface kits and decorations), as Low Water already
does. `docs/protocol.md` is updated.

## The map

72 by 56 m inside a 76 m square (wall bands fill the strip). Five walking
levels: Pit 0.0, the Rail landing 0.5, level 1 at 1.5 (Lane, Stands,
Impound), level 2 at 3.0 (Toll, Bridge, Crane), level 3 at 4.5 (Gallery,
Spiral landing), Roof 6.0. Six slabs have a floor beneath them: the Bridge,
the Low Ramp lid, the two bay ceilings, the Toll canopy and the hung cruiser
(10 to 14.5 m, above any head).

Seventeen callouts (test-side ids, client signs keyed `WORLD_LARAK_*`): PIT,
STACK, STANDS, LOW RAMP, LANE, PAY DOOR, TOLL, BOOTHS, BRIDGE, GALLERY,
SPIRAL, ROOF, SIGN, FIRE STAIR, CRANE, STAIR B, IMPOUND.

Pads: Custody Plate (armour to 100, 35 s) in the Roof valet circle; Rail on
the Low Ramp landing (25 s); Scatter at the Booths and the foot of Stair B;
Flechette in the Pit and the Lane; Bridge armour +25 (out of claim reach from
the Pit); health at the Toll cashier, Stands and Crane.

Landmarks: THE REPOSSESSION, a Union Compliance cruiser hung nose-down from a
tower crane over the Pit, wrapped in a league banner, with work floods and a
strobing light bar; and the LARAK neon blade sign behind the Plate, whose K
keeps dropping out.

Changes against the spec, each re-measured:

- Thin wall tops are raised past the 20 Hz jump apex (Roof walls 7.6, valet
  barriers 7.4, the Low Ramp's north wall 4.0 as a sight screen) so no wall
  becomes a perch. `larak_overlaps_unreachable_tops` checks every one.
- The bookmaker kiosk carries a tote board back to the viaduct wall, so the
  south level-one strip is two bays rather than one 70 m lane.
- Two rows of bettors' car seats (0.9 m, half cover) on the Stands, the one
  deck that was otherwise a flat field.
- Two shear walls (to the 4.6 m soffit, each with a 3 m door) between the
  Stands and the Lane and Impound bays. Level one was one 70 m lane along the
  viaduct wall; the Stands, Lane and Impound slots saw one another down it.
- Two slots moved after a playtest showed spawn deaths clustering in exposed
  places: S2 from the Toll's open west edge to the cashier lane behind the
  first booth, and S11 from the Impound Skids (the most exposed slot, 50% of
  reachable eyes within 40 m) to the Stands behind the tote board. The Impound
  keeps two slots; it is the Plate's side of the map.

## Measurements

Layered Dijkstra over 1 m cells with the server's own collision and line of
sight at `TOP_SPEED` (5 m/s): lower bounds; a fighter turning and shooting is
slower. Printed by
`cargo test -p fragr-server --lib larak_measured_table -- --ignored --nocapture`.

| Route | Measured | Gate |
|---|---|---|
| SW Lane corner to NE Roof corner | 19.4 s | under 25 s |
| NW Toll corner to SE Impound corner | 18.4 s | under 25 s |
| Rail to Plate (climb) | 17.1 s | under 25 s |
| Plate to Rail (fall) | 14.1 s | under 25 s |
| Pit origin to Flechette / Rail / Bridge armour / Plate | 1.2 / 4.6 / 6.0 / 14.7 s | |
| Pit origin to Booths Scatter / Stair B Scatter | 6.3 / 6.7 s | |

| Slot | Quarter | Nearest weapon | To Plate | To Rail | Sees Plate or Rail |
|---|---|---|---|---|---|
| S1 (-33, 3.0, -27) | Toll | Booths Scatter 3.7 s | 16.4 s | 8.3 s | no |
| S2 (-33.5, 3.0, -15.5) | Toll | Booths Scatter 3.6 s | 16.8 s | 6.0 s | no |
| S3 (-27, 3.0, -15) | Booths | Booths Scatter 2.5 s | 15.5 s | 5.5 s | no |
| S4 (-17, 3.0, -23) | Toll | Booths Scatter 1.9 s | 12.9 s | 7.4 s | no |
| S5 (-3, 4.5, -26) | Spiral | Booths Scatter 4.9 s | 10.3 s | 8.4 s | no |
| S6 (-31, 1.5, 25) | Lane | Lane Flechette 1.9 s | 20.5 s | 4.8 s | no |
| S7 (-34, 1.5, 20) | Lane | Lane Flechette 1.0 s | 19.7 s | 4.5 s | no |
| S8 (-5, 1.5, 25) | Stands | Pit Flechette 4.6 s | 16.5 s | 5.4 s | no |
| S9 (7, 1.5, 23) | Stands | Pit Flechette 4.8 s | 13.0 s | 7.4 s | no |
| S10 (19, 1.5, 25) | Impound | Stair B Scatter 4.0 s | 11.7 s | 9.5 s | no |
| S11 (2.5, 1.5, 24.5) | Stands | Pit Flechette 4.9 s | 13.9 s | 7.5 s | no |
| S12 (25, 1.5, 26) | Impound | Stair B Scatter 3.9 s | 11.6 s | 10.8 s | no |

The Rail and the Plate have no line of sight to each other. The Repossession
is visible from 83% of 3,137 reachable standing cells and the LARAK sign from
81%, measured with the hung cruiser's own collision box in place.

Spawn-to-spawn sight (standing eye to a standing body) after the shear walls:
the Toll slots see each other at 12 to 16 m, S4 and S5 see the far Lane and
Stands at 46 to 58 m, and two pairs share a room (S9 and S11 at 5 m, S10 and
S12 at 6 m). The Lane, Stands and Impound slots no longer see one another.
`larak_spawn_exposure` (ignored) prints each slot's share of reachable eyes
within 40 m: 16 to 38% (S4 and S5 at the Spiral are the most exposed).

## Verification

Cargo tests in `server/src/maps/larak_lot/tests.rs`:
`larak_layout_validates_and_keeps_the_episode_origin_clear`,
`larak_every_pad_and_spawn_reachable`,
`larak_pads_and_spawns_have_headroom_and_no_claim_from_above`,
`larak_spawn_never_sees_power_item`, `larak_rail_plate_no_los`,
`larak_spawn_power_distance`, `larak_every_spawn_within_5s_of_weapon_pad`,
`larak_corner_to_corner_under_25s`, `larak_overlaps_unreachable_tops`,
`larak_bridge_armor_out_of_pit_claim`, `larak_gallery_bridge_gap_jump`,
`larak_spawn_slots_wrap_and_face_their_quarter`,
`larak_callouts_name_every_pad_and_separate_the_bridge_from_the_pit`,
`larak_presentation_matches_collision_and_budgets`,
`larak_pads_run_their_own_clocks`. Godot: `client/scripts/test_larak_lot.gd`
(no collision, light budget, replaced boxes, catalog copy, the K drop-out).

Rendered review: `tools/preview_larak_lot.gd` renders 30 stills (every
quarter, both landmarks, overviews and first person at all twelve slots) from
the server's own MapInfo with the match's sky, lights and quality settings.
Seven rounds were captured and critiqued; see [Visual rounds](#visual-rounds).
`client/qa/larak_lot.json` is the live review manifest with bots, pads and a
joined first-person fighter.

### Playtest harness, before and after

Agents are the harness's reflex and planner clients on loopback, seed 42,
one 120 s window unless noted. "Before" is `origin/main` (Arena Duel) built
from the same commit's parent; "after" is this branch. Debug builds on a
shared, loaded machine. Kill distance shares are of 5 m buckets.

| Run | Map | Frags/min | First frag | Spawn deaths / frags (opening) | Pad claims | Kills under 5 m / 5 to 10 m / 10 m and over |
|---|---|---|---|---|---|---|
| CI smoke, 4 agents, frag limit 3, `--assert` | Arena Duel | 15.3 | 9.0 s | 0 / 8 (0) | 1 | 50 / 12 / 37% |
| CI smoke, 4 agents, frag limit 3, `--assert` | Larak Lot | 20.0 | 4.4 s | 0 / 4 (0), passed | 1 | 50 / 50 / 0% |
| FFA, 8 agents | Arena Duel | 49.5 | 4.3 s | 3 / 99 (0) | 5 | 14 / 56 / 30% |
| FFA, 8 agents | Larak Lot | 67.5 | 3.8 s | 33 / 135 (2) | 4 | 44 / 36 / 20% |
| FFA, 6 agents | Arena Duel | 30.5 | 4.4 s | 5 / 61 (0) | 2 | 36 / 43 / 21% |
| FFA, 6 agents | Larak Lot | 45.5 | 4.0 s | 17 / 91 (0) | 4 | 52 / 30 / 19% |
| Duel, 2 agents | Arena Duel | 6.0 | 11.5 s | 0 / 12 (0) | 1 | 33 / 17 / 50% |
| Duel, 2 agents | Larak Lot | 6.5 | 15.8 s | 0 / 13 (0) | 0 | 23 / 62 / 16% |
| Roster case (map 1, 2 agents, seed 67, reflex and planner, `--assert`) | Larak Lot | 5.8 | 11.1 s | 0 / 6 (0), passed | 4 | 0 / 17 / 83% |

Read honestly:

- Fights come faster and more often: 45.5 frags a minute at six against
  30.5, first frag about 4 s. The spec's floor (12 a minute at six, ideally
  15 or more) is cleared.
- **Spawn deaths are the open problem.** At six and eight agents 19 to 24%
  of deaths land within 2 s of a respawn, against 3 to 8% on the old field;
  both would fail the harness's 10% spawn-death gate, which CI applies only to
  the two-agent map 1 roster case (passed). The evidence log names killers
  3 to 16 m from the slot: an opponent already round the corner rather than a
  long lane, on a map where these near-perfect agents average a seven second
  life. The shear walls and two moved slots cut spawn-to-spawn sight and slot
  exposure but not the rate (34 to 39 before, 33 after, at eight). The gated
  spawn area is small by design (no slot may see the Plate or the Rail or sit
  within 10 s of the Plate), so the next levers are a route-distance threat
  term in `select_spawn`, more slots in the Toll and bays, or a longer shield
  on compact maps. Human sessions decide whether it matters at human aim.
- Pad claims stay low because the playtest agents fight rather than route to
  pads; the server's rule bots do collect the Rail and Scatters (seen in a
  60 s, eight-bot tick trace). Plate contest needs the A1 pad contest index
  and human or planner sessions.
- The CPU benchmark (`--bench 16 --bench-ticks 1200 --bench-check
  --bench-assert --seed 42`, release) passes and is deterministic; p99 tick
  budget use is 2.0%. Its final frag table reads all zeros only because the
  sixteen bots reached the frag limit and a new round reset the scores.

## Visual rounds

1. First port: grey slabs, flat sky key. Added the venue sky, sodium
   practicals, level colour bands, hazard edges on every ledge, tread nosing.
2. Landmarks: the hung cruiser read as a box from the Toll; rebuilt it as a
   car inside its volume with the hook, work-light ring and strobing bar, and
   the crane over the Roof. The LARAK blade gained a bulb border.
3. Story: Ledger Wall, odds board, booths sprayed over, pay machines signed by
   Larak, Aunt Linda's tent revival, the transit train, water streaks.
4. Floors were still flat fields in the Stands and Impound: added the seat
   rows (collision), floor level stencils, skid marks, betting slips, scorch,
   puddles and headroom bars; rebuilt the Roof van so it reads as a
   Compliance van on its side.
5. The van's roof face now wears the bone Compliance roof, band and spray;
   the shell tops and the Roof drive lane were too dark and read as voids.
6. Puddles and scorch were hard geometric quads; softened to single pools and
   irregular marks.
7. The shear walls carry the level-one green band and a vent; S2 and S11
   first-person views checked.

## Asset wishes for the next paid round

Not generated in this lane. For the Meshy and Higgsfield round:

- A Union Compliance cruiser and van model (black, bone doors, red band, light
  bar), to replace the box-built vehicles inside the same collision volumes.
- A crushed-car stack and a burnt tow truck for THE STACK.
- A tower crane with hook block and work-light ring.
- Car-seat and pallet bleacher modules; a bookmaker kiosk with chalk board.
- Decals: oil stains, tyre skids, betting slips, Larak's signature stamp,
  league tags, wet concrete with drain grates.
- Audio: crowd murmur from the Stands, crane cable creak, neon buzz, rain
  through the Pit lightwell, the Plate's custody-lock clunk.

## Open

- Human sessions in Duel and FFA; the playtest agents do not establish fun.
- `PickupKind::Plate`, the Tack and Fists kit, the Plate clunk and Host line.
- Phase-two decoration kinds (LotLevelNumber, LeagueBanner, LedgerWall,
  TollPriceBoard) as registered panels; today the presenter paints them.
- `tools/qa_tour.sh --publish` needs Xvfb, which this Linux machine lacks, and
  a direct windowed run of `client/qa/larak_lot.json` under a tiling Wayland
  window manager fails the tour's capture-size check (window resized to
  1090 x 688). The README stills from the tour still show the Arena Duel field
  until the tour runs on a machine with Xvfb or a fixed window.
- The Roof loop is 47 s by the spec model; watch whether the Plate goes
  uncontested in Duel. The lever is a Roof south-west parapet gap onto the
  Bridge end.
