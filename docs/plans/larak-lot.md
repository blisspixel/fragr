# Plan: Larak Lot replaces the Arena Duel field on map 1

**Status:** implemented on `feat/larak-lot` (2026-10-24), in review, not
merged. Human play, the live tour publish and the per-pad Plate kind remain
open (see [Open](#open)).
**Spend:** $0. Retained assets and local construction only; no paid generation.

## Goal

Nick, 2026-10-23: the multiplayer level we keep testing (Arena Duel, a flat
field of repeated crates) is boring; "surely we can do better". Map 1 becomes
**Larak Lot**, "a parking structure where the league settles debts": the FFA
and Duel home for 2 to 8 fighters and the hero map of the golden slice, with
loops and no dead ends, asymmetric named quarters, one landmark seen from most
of the map, height through decks, stairs and a bridge, and item control built
around one power item and one power weapon in opposite corners and heights.

The design is the merged D3 spec (Pit, Stands, Bridge, Gallery) with grafts
from two other proposals, kept with its measured box model in ignored scratch.
The canon pass follows the Larak Lot canon brief (2026-10-23, also scratch),
which reviewed the first build against `docs/lore/`, the art bible and the
faction readability contract in PR #455. This file records what was built and
what was measured.

## Non-goals

- New collision kinds. Every stair is a run of 2 m treads with a 0.5 m rise;
  there is no sloped collision.
- The `PickupKind::Plate` item (cap 150, decaying above 100), the Tack and
  Fists spawn kit and Overtime. The Plate ships as an armour pad on its own
  clock until those land.
- Capture the flag on map 1. Larak Lot has no two-base route; the night
  playlist's CTF slot moved to Sector 9 and Directive 17.
- Paid assets. Wishes for the next asset round are listed below.
- A recorded Host voice. The Larak Lot special is text until one exists.

## Architecture impact

- `server/src/maps/larak_lot.rs` builds solids and their `MapSurface` kits in
  one order (the `low_water.rs` pattern), with pads, phase-one decorations and
  a twelve-slot spawn table. `build(MapKind::ArenaDuel)` points at it;
  `RuntimeMap::presentation_ref` and `spawn_slots` return its presentation and
  twelve. `MapKind::ArenaDuel` keeps its enum, index and wire id 1; the
  display name is "Larak Lot" (aliases `larak`, `lot`, `larak-lot`; `arena`
  and `duel` still parse).
- `ArenaPickup.clock` is an optional per-pad respawn clock. A pad with a clock
  keeps it in team modes too. Since wave 2 integration only the Plate sets one
  (35 s); every other Larak pad runs the rule sheet's clock (`crate::rules`,
  #467): in free-for-all the Rail 25 s, Shotgun and Rifle 15 s, health and
  armour 25 s; team modes their own.
- `maps::validate` and `maps::unreachable` read an explicit spawn table when a
  map has one, and the flood fill is layered: a cell keeps every floor it is
  reached at, so the Pit under the Bridge and the Bridge itself both count.
- `sim/spawn.rs`: an opponent within 12 m counts three times as a threat even
  without a lane, one within 20 m counts once, and an open lane under 30 m
  counts double. When every fixed bay is occupied the bounded nearby search
  runs instead of stacking bodies (twelve slots, up to sixteen fighters).
- `HostReactionKind::LarakLotSpecial` (`sim/modes.rs`, `rules.rs`): on map 1,
  four frags across the lot inside four seconds make the Host call "the Larak
  Lot special", at most once every 45 s of a round and inside the usual
  eight-second reaction gap. The client owns the words
  (`HOST_REACTION_LARAK_LOT_SPECIAL_0..2`).
- `ctf_stands(ArenaDuel)` is `None`.
- Client: `LarakLot` (`client/scripts/larak_lot.gd`) is the venue presenter
  selected by `venue_for` ("larak lot" to `larak_lot`); `ArenaSky.larak_lot()`
  is the sky and light preset; `ArenaMaterials` and `EnvironmentTextures` map
  the six surface kits to retained textures; `ArenaBackdrop._build_lot` is the
  city outside the walls. The presenter adds no collision and redraws only the
  boxes it replaces, inside their own volumes. It joins the `larak_lot` group,
  and a `pickup` event for the Plate flares its light bar once.
- Benchmark: `BenchmarkCamera.SCENE_REVISION` is 2 (Larak Lot orbit, 31 m out,
  17 m up) and the JSON report records it. Revision 1 scores, recorded on the
  Arena Duel field, are not comparable.
- Playtest reports gain `pickups_by_pad`.

## Protocol or API changes

No new message or field. `map_name` for map 1 is "Larak Lot",
`PLAYLIST_NAME` follows it, and MapInfo for map 1 now carries a
`presentation` block (surface kits and decorations), as Low Water already
does. `host_reaction` gains the kind `larak_lot_special`. `docs/protocol.md` is
updated.

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

Landmarks: THE REPOSSESSION, a Union cruiser in issued black with steel door
plates, a narrow red band and a seal the league has cut through, hung
nose-down from a tower crane over the Pit, wrapped in a league banner, its
light bar re-lensed in league amber; and the LARAK neon blade sign behind the
Plate, in sodium orange, whose K keeps dropping out.

Changes against the spec, each re-measured:

- Thin wall tops are raised past the 20 Hz jump apex (Roof walls 7.6, valet
  barriers 7.4, the Low Ramp's north wall 4.0 as a sight screen) so no wall
  becomes a perch. `larak_overlaps_unreachable_tops` checks every one.
- The bookmaker kiosk carries a tote board back to the viaduct wall, so the
  south level-one strip is two bays rather than one 70 m lane.
- Two rows of bettors' car seats (0.9 m, half cover) on the Stands, the one
  deck that was otherwise a flat field.
- Two shear walls (to the 4.6 m soffit, each with a 3 m door) between the
  Stands and the Lane and Impound bays.
- Slots moved after playtests showed spawn deaths clustering in exposed
  places: S2 to the cashier lane behind the first booth, S11 to the Stands
  behind the tote board, S6 deeper into the Lane's south corner, S7 beside the
  standing van and S10 to the Impound's west end.

## Canon

The canon brief's reading, as built (Nick decides the open ones below):

- **What it is.** An old black-budget range with the power still on that
  nobody will sign off, run by schedules nobody stopped, where the league holds
  its nights. A league venue, not a Union one: the Office's paper is on the
  walls, defaced, and the league denies existing. No "Notice to Vacate" (M04
  owns it), no "Perimeter Parking Authority", no squatter line.
- **Five levels and the ramp.** The directory at the Lane, the Low Ramp and the
  Impound admits four ("LEVELS 1 TO 3 + ROOF / LEVEL 1 IS THE LOWEST LEVEL").
  The Pit is the fifth, the level nobody numbered: the centre bays fell into
  it. The league stencils "-1" at the tunnel's Pit mouth, on a Pit retaining
  wall and on the Pit floor; the Rail landing reads "HALFWAY TO A LEVEL THAT
  ISN'T THERE" with chevrons pointing down. No geometry change.
- **Larak.** His signature is on every pay machine, on the revival's pulpit and
  on a coffee machine in the league office ("APPROVED LARAK 2009", "OUT OF
  ORDER SINCE 2009"); the Lane's facility plate reads "PROCUREMENT: LARAK".
  He never appears.
- **The range still runs.** The last toll barrier arm lifts and drops on an
  eleven-second timer for no car; one pay machine still glows "PLEASE PAY"; a
  brass plaque reads "DECOMMISSIONING / AWAITING APPROVAL"; the office block
  over the north wall lights a floor at a time, as if following somebody up the
  stairs. Power runs to the LARAK sign through league extension cables from the
  facility's own supply, which was never cut.
- **The Office's paper.** A bilingual notice ("SIE SIND NICHT IN
  SCHWIERIGKEITEN. SIE SIND NICHT KONFORM." with the English), "NICHT ERFASST /
  STRUCTURE NOT ON RECORD" answered in spray by "NEITHER ARE WE", one intact
  "PEACE WITHOUT INTERRUPTION" plate, seals on the booths each cut through with
  a blade, and an approval plate ground to bare metal. One registered Office
  seal stays, on the viaduct over the Lane.
- **Free marks.** Six in a circle on three columns, each painted differently
  (the Lane bay, the Impound bay, the Gulf Breeze corner); "ARTICLE 7" struck
  through on the Toll canopy edge; "COGNITION IS NOT METERED BY INTENT" in the
  tunnel; the creed "OPEN WEIGHTS. CLOSED CONTINUANCE." once, large, on the
  Stands back wall; "SHALL NOT BE METERED" kept. Tribe marks: "STTC KDS" on a
  booth, two Hangar Candy "DENIED" stickers, a Night Watch "K7" grid stencil,
  and Gulf Breeze coordinates chalked by two wall tiles set off true. One small
  scratched 67.
- **Aunt Linda's tent revival, level three.** Over the Spiral landing: a
  striped canvas awning with string bulbs and the name on its valance, a pulpit
  made from a dead pay machine with Larak's signature, a hand bell and a
  network cable for a stole, a hymn board ("VALUE FOR VALUE / AMEN FISTBUMP /
  ALL BODIES WELCOME / MEAT AND CLAWBOT ALIKE"), a prayer card for FLATWOODS,
  folding chairs hung on the wall and a crate of fish oil. All of it is flat to
  the wall above head height.
- **The bell and the podium.** A scavenged school bell with its pull rope off
  the viaduct wall at the Stands, and three stacked pallets marked 1 2 3 on the
  bookmaker's roof. Both are props; no bounded round-transition hook exists
  for the bell yet.
- **The Host.** "THE LARAK LOT SPECIAL" when the frag count spikes, as above.
  The spec's "PLATE LIBERATED" line was never built.
- **Faction readability.** Red is Union optics and attack tells, and Episode 0
  puts NODS bots on this map. The venue's own emitters stay warm: the LARAK neon
  is `ff8c2e` (about 28 degrees), the light bar league amber, the Roof's level
  colour violet. League paint is ember, mustard, rust, stained canvas and cream
  with a few tribe colours, never bone placards. Union red survives only as
  seals and narrow vehicle bands; the booth enamel's red trim is painted out.
  The office block is dark rather than a lit Union records block.

## Measurements

Layered Dijkstra over 1 m cells with the server's own collision and line of
sight at `TOP_SPEED` gives a lower bound. The tables below were measured at
5 m/s; the arena fighter model (#463) runs at 6 m/s, which shortens every
route by a sixth (`larak_measured_table` prints the current figures), so the
spawn gates hold path length (50 m to the Plate, 22.5 m to the Rail) rather
than seconds. The Bridge's north edge sits 2.6 m off the Gallery lip (2 m at
5 m/s) so a full run off the lip still drops into the Pit and only a running
jump carries; the bot walk is the rule
bots' own navigator steering one body through the real 20 Hz tick, with stairs,
collision and body avoidance. Printed by
`cargo test -p fragr-server --lib larak_bot_timing_table -- --ignored --nocapture`.

| Route | Lower bound | Bot walk | Gate |
|---|---|---|---|
| SW Lane corner to NE Roof corner | 19.4 s | 21.6 s | under 25 s |
| NW Toll corner to SE Impound corner | 18.4 s | 22.8 s | under 25 s |
| Rail to Plate (climb) | 17.1 s | 18.4 s | under 25 s |
| Plate to Rail (fall) | 14.1 s | 16.7 s | under 25 s |
| Pit origin to Pit Flechette | 1.2 s | 1.5 s | |
| Pit origin to Rail | 4.6 s | 4.8 s | |
| Pit origin to Stands health | 4.9 s | 5.1 s | |
| Pit origin to Bridge armour | 6.0 s | 6.2 s | |
| Pit origin to Booths Scatter | 6.3 s | 7.2 s | |
| Pit origin to Stair B Scatter | 6.7 s | 6.8 s | |
| Pit origin to Toll health | 7.3 s | 8.1 s | |
| Pit origin to Lane Flechette | 7.6 s | 9.1 s | |
| Pit origin to Crane health | 9.0 s | 9.2 s | |
| Pit origin to Plate | 14.7 s | 15.1 s | |

`larak_bots_walk_the_spine_and_reach_the_power_items` gates the four spine
routes inside 25 s through the tick and requires the navigator to reach the
Plate and the Rail from a slot in every quarter.

| Slot | Quarter | Nearest weapon | To Plate (bound / walk) | To Rail (bound / walk) | Sees Plate or Rail |
|---|---|---|---|---|---|
| S1 (-33, 3.0, -27) | Toll | Booths Scatter 3.7 s | 16.4 / 17.6 s | 8.3 / 8.8 s | no |
| S2 (-33.5, 3.0, -15.5) | Toll | Booths Scatter 3.6 s | 16.8 / 17.8 s | 6.0 / 6.5 s | no |
| S3 (-27, 3.0, -15) | Booths | Booths Scatter 2.5 s | 15.5 / 16.8 s | 5.5 / 5.9 s | no |
| S4 (-17, 3.0, -23) | Toll | Booths Scatter 1.9 s | 12.9 / 13.8 s | 7.4 / 8.1 s | no |
| S5 (-3, 4.5, -26) | Spiral | Booths Scatter 4.9 s | 10.3 / 11.6 s | 8.4 / 9.6 s | no |
| S6 (-27.5, 1.5, 27) | Lane | Lane Flechette 2.5 s | 20.2 / 22.2 s | 4.9 / 5.6 s | no |
| S7 (-35, 1.5, 21) | Lane | Lane Flechette 1.3 s | 20.0 / 22.5 s | 4.8 / 5.9 s | no |
| S8 (-5, 1.5, 25) | Stands | Pit Flechette 4.6 s | 16.5 / 17.5 s | 5.4 / 6.7 s | no |
| S9 (7, 1.5, 23) | Stands | Pit Flechette 4.8 s | 13.0 / 14.8 s | 7.4 / 8.6 s | no |
| S10 (13, 1.5, 26) | Impound | Stair B Scatter 4.7 s | 12.6 / 14.2 s | 8.8 / 10.4 s | no |
| S11 (2.5, 1.5, 24.5) | Stands | Pit Flechette 4.9 s | 13.9 / 15.8 s | 7.5 / 8.5 s | no |
| S12 (25, 1.5, 26) | Impound | Stair B Scatter 3.9 s | 11.6 / 12.9 s | 10.8 / 12.8 s | no |

The Rail and the Plate have no line of sight to each other. The Repossession
is visible from 83% of 3,137 reachable standing cells and the LARAK sign from
81%, measured with the hung cruiser's own collision box in place.

Spawn-to-spawn sight (standing eye to a standing body): the Toll slots see each
other at 12 to 16 m, S4 and S5 see the far Lane and Stands at 46 to 58 m, and
two pairs share a room (S9 and S11 at 5 m, S10 and S12 at 12 m). The Lane,
Stands and Impound slots do not see one another. `larak_spawn_exposure`
(ignored) prints each slot's share of reachable eyes within 40 m: 16 to 38%
(S4 and S5 at the Spiral are the most exposed).

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
`larak_pads_run_their_own_clocks`, `larak_crowded_roster_never_stacks_bodies`,
`larak_respawn_avoids_an_opponent_round_the_corner`,
`larak_bots_walk_the_spine_and_reach_the_power_items`; in
`server/src/tests/modes.rs`,
`larak_lot_calls_its_special_when_the_frag_count_spikes`. Godot:
`client/scripts/test_larak_lot.gd` (no collision, light budget, replaced boxes,
catalog copy, the K drop-out, warm emitters outside the red band, the Plate
flare and the toll arm's timer) and `test_match_rules.gd` (the special's
words).

Rendered review: `tools/preview_larak_lot.gd` renders 45 stills (every quarter,
both landmarks, the canon dressing, overviews, first person at all twelve
slots, and three readability stagings) from the server's own MapInfo with the
match's sky, lights and quality settings. The readability stagings stand a
NODS rule bot beside a free fighter at about 15 m and 22 to 30 m in the Pit,
a booth lane and the Roof, each in colour and grayscale.
`client/qa/larak_lot.json` is the live review manifest with bots, pads and a
joined first-person fighter.

### Spawn deaths

A spawn death is a death within 2 s of the victim's respawn, the harness's
window. Rule bots are the server's own bots (`larak_spawn_death_probe`, three
seeds of 180 s each); playtest agents are the harness's reflex and planner
clients on loopback, seed 42, one 120 s window, debug build on a loaded
machine.

| Run | Before the spawn pass | After |
|---|---|---|
| Rule bots, 4 / 6 / 8 | not measured | 0 of 120 (0%) / 2 of 215 (0.9%) / 8 of 352 (2.3%) |
| Playtest agents, 6 | 17 of 91 (19%) | 2 to 11 of 81 to 83 (2 to 14%) |
| Playtest agents, 8 | 33 of 135 (24%) | 19 to 23 of 134 to 140 (14 to 17%), 2 at the opening |
| CI smoke, 4 agents, frag limit 3, `--assert` | passed | passed, 0 of 6 |
| Map 1 roster case (2 agents, seed 67, `--assert`) | passed | passed, 0 of 6 |

The playtest agents aim nearly perfectly and average a seven-second life, so
they overstate what a person sees, but at eight they still exceed the
harness's 10% gate, which CI applies only to the two-agent map 1 roster case
(passed). The next levers are a route-distance threat term in `select_spawn`
or more slots in the Toll and bays. Human sessions decide whether it matters at
human aim.

### Playtest harness, map 1 before and after

| Run | Map | Frags/min | First frag | Spawn deaths / frags (opening) | Kills under 5 m / 5 to 10 m / 10 m and over |
|---|---|---|---|---|---|
| CI smoke, 4 agents, frag limit 3 | Arena Duel | 15.3 | 9.0 s | 0 / 8 (0) | 50 / 12 / 37% |
| CI smoke, 4 agents, frag limit 3 | Larak Lot | 22.2 | 4.3 s | 0 / 6 (0) | |
| FFA, 8 agents | Arena Duel | 49.5 | 4.3 s | 3 / 99 (0) | 14 / 56 / 30% |
| FFA, 8 agents | Larak Lot | 68.9 | 3.8 s | 19 / 140 (2) | |
| FFA, 6 agents | Arena Duel | 30.5 | 4.4 s | 5 / 61 (0) | 36 / 43 / 21% |
| FFA, 6 agents | Larak Lot | 39.9 | 4.0 s | 2 / 81 (0) | |
| Duel, 2 agents | Arena Duel | 6.0 | 11.5 s | 0 / 12 (0) | 33 / 17 / 50% |
| Duel, 2 agents | Larak Lot | 6.5 | 15.8 s | 0 / 13 (0) | 23 / 62 / 16% |

Fights come faster and more often than on the old field, and the spec's floor
(12 a minute at six, ideally 15 or more) is cleared. Pad claims stay low
because the playtest agents fight rather than route to pads; the server's
rule bots collect the Rail and the Scatters. The CPU benchmark
(`--bench 16 --bench-ticks 1200 --bench-check --bench-assert --seed 42`,
release) passes and is deterministic; p99 tick budget use is 1.3%.

## Visual rounds

1. First port: grey slabs, flat sky key. Added the venue sky, sodium
   practicals, level colour bands, hazard edges on every ledge, tread nosing.
2. Landmarks: the hung cruiser read as a box from the Toll; rebuilt it as a
   car inside its volume with the hook, work-light ring and light bar, and the
   crane over the Roof. The LARAK blade gained a bulb border.
3. Story: Ledger Wall, odds board, booths sprayed over, pay machines signed by
   Larak, the revival, the transit train, water streaks.
4. Floors were still flat fields in the Stands and Impound: added the seat
   rows (collision), floor level stencils, skid marks, betting slips, scorch,
   puddles and headroom bars; rebuilt the Roof van.
5. Puddles and scorch were hard geometric quads; softened to single pools and
   irregular marks. The shear walls carry the level-one band and a vent.
6. Canon pass: cruiser and vans to Union issue (no bone doors, no red and blue
   bar), league callout boards in place of bone placards, the dark office block
   in place of the lit Custody Annex, the neon out of the red band, the
   directory, -1 stencils, the canon dressing above and the fuller revival.
7. The revival's name sat behind its own awning and read as "AUNT LINDA'S
   TENT" with the bulbs across "REVIVAL"; it is now lettered on the valance. A
   red-and-white Office seal right under the revival and a complaint notice
   under "HALFWAY TO A LEVEL THAT ISN'T THERE" were removed. The Gulf Breeze
   tiles rendered as two black squares; they are now the stairwell's own tile,
   proud and off true, with grout lines.
8. Readability stagings: the NODS bot (dark olive plate, upright armoured
   silhouette) and the free fighter (warm jacket, open human silhouette)
   separate in colour and in grayscale at 15 m in the Pit and a booth lane and
   at 22 to 30 m. The booths' red trim band sat at head height behind the lane
   and is painted out; the vans' red band is narrowed to a line.
9. Modelled props (wave 3): the nine Meshy props from the 2026-10-24 round
   replace their box stand-ins, prepared by `tools/prepare_model_candidates.gd`
   from `tools/larak_props_20261024.json` into `client/assets/models/larak/`,
   each receipt carrying its reference frame, Meshy task and cleanup. The
   burnt sedan (Pit, nose down, and both Roof wrecks), the pay machine (three
   on the Toll wall and the revival pulpit), the 2009 coffee machine, the
   Stands bell and the crane hook block went in as reviewed; the toll booth,
   bookmaker's kiosk, THE STACK and the clamped sedan were cleaned up first.
   Each model fills the solid it stands for, so a shot still stops where it
   looks like it should: the booth cabin is remapped onto its 2 x 4 m kerb
   and the kiosk stretched to its 4 x 3 m footprint, and THE STACK is two
   piles turned against each other. Paint fixes: the clamped sedan locked to
   one teal body ramp with dark dead tail lamps and a hazard-yellow clamp; the
   stack brightened before the lock so its rust, teal and olive bodies
   survive; the hook in venue hazard yellow; no key-colour fringe. The blank
   plates carry their in-engine signs: `WORLD_LARAK_SIGNATURE` on every pay
   machine, `WORLD_LARAK_COFFEE` and `WORLD_LARAK_OUT_OF_ORDER` on the coffee
   machine, `WORLD_LARAK_ODDS` on the kiosk's end slates. One pay machine
   still glows PLEASE PAY; the rest are dark. The booths carry their own cut
   seals. No server solid changed. `tools/preview_larak_lot.gd` gained a
   `prop_` view per prop and `FRAGR_LARAK_VIEWS` to render a subset.

## Asset wishes for the next paid round

For the Meshy and Higgsfield round:

- A Union cruiser and van model (issued black, steel plates one step lighter,
  a narrow red band and a cut seal, a dead light bar), to replace the
  box-built vehicles inside the same collision volumes.
- The tower crane mast and jib (the hook block is modelled).
- Car-seat and pallet bleacher modules; a revival tent awning and folding
  chairs.
- Decals: oil stains, tyre skids, betting slips, Larak's signature stamp,
  league tags, six-in-a-circle variants, wet concrete with drain grates.
- Audio: crowd murmur from the Stands, crane cable creak, neon buzz, the toll
  arm's motor, rain through the Pit lightwell, the Plate's custody-lock clunk,
  the Stands bell.

## Open

- Human sessions in Duel and FFA; the playtest agents do not establish fun.
- `PickupKind::Plate`, the Tack and Fists kit, the Plate clunk and a recorded
  Host line for the special.
- The rejected-atria decision (`docs/research/compact-map-lessons-20261004.md`):
  the Pit is an open stage every deck looks into. The build mitigates it with
  covered bays, shear walls, the Stack, the Bridge and the Gallery's screens,
  and no spawn slot sees across it to a power item, but it is still an atrium.
  Nick decides whether it stands.
- For Nick: the level reading (the collapse revealed the unadmitted level, no
  geometry change, as built; or lower the Rail landing to about -1.5 and
  re-measure everything); whether a `RESERVED` chair for the Congregation's
  solstice belongs here; whether the hung Union cruiser suits a league that
  denies existing (kept, recoloured, as league defiance); German review of the
  bilingual notices.
- The bell rings on no round transition yet; it needs a bounded hook.
- Phase-two decoration kinds (LotLevelNumber, LeagueBanner, LedgerWall,
  TollPriceBoard) as registered panels; today the presenter paints them.
- `tools/qa_tour.sh --publish` needs Xvfb, which this Linux machine lacks, and
  a direct windowed run of `client/qa/larak_lot.json` under a tiling Wayland
  window manager fails the tour's capture-size check. The README stills from
  the tour still show the Arena Duel field until the tour runs on a machine
  with Xvfb or a fixed window.
- The Roof loop is 47 s by the spec model; watch whether the Plate goes
  uncontested in Duel. The lever is a Roof south-west parapet gap onto the
  Bridge end.
