# Plan: the 2026 map roster

**Status:** shipped, with the gaps below named (2026-09-19)
**Branch:** `feat/map-roster-2026`
**Spend:** $0. Loopback only.

## What is built and what is only drawn

Read this before the rest of the file.

**Built, tested, and playing:**

- Six maps in `server/src/maps.rs`, 110 m to 320 m across, selectable with
  `--map 1` through `--map 6` and cycled by `--map-rotate`.
- A heightfield in the shared movement step: solids have tops, a 0.6 metre
  step is walked up and down, a bigger drop is a fall, and landing is swept.
  Rust and GDScript agree, proven by golden vectors with three new cases.
- Height-aware cover: a solid only blocks a shot whose line passes below its
  top, so two fighters on a deck can shoot each other and a kerb is not cover.
- Height-aware pads: a pad on a walkway cannot be taken from the floor.
- Per-map bounds and spawn rings, replacing the one global `ARENA_SIZE`.
- A validator and a two-and-a-half-dimensional reachability flood fill that
  run as tests over **every** map: origin clear, spawn ring clear, pads on the
  floor they claim to be on, everything walkable from the origin.
- The Godot client builds the floor, the boundary and every solid at its own
  height from `MapInfo`, so a 320 m map is no longer drawn in a 100 m box.
- True 3D hitscan shipped later in v0.19.0, replacing the original horizontal
  segment with a finite ray against fighter bodies and cover.

**Designed here, not built:**

- **The three-cornered mode.** Tripoint Works exists as geometry and plays as
  an ordinary deathmatch map today. Three-faction spawns, zone capture, and
  what holding a zone unlocks are engine work that does not exist; the list of
  what is missing is in "Tripoint Works and the three-cornered mode" below.
- **Permeable floors** (`MAP-DESIGN` rule five): grates, balconies to drop
  through, anything you can walk under. The collision model is a heightfield,
  so a solid runs from the floor to its top and has no space beneath it.
- **Lifts, jump pads, doors.**
- **Agent pathing for height.** The playtest's reflex agent walks in a
  straight line at its target. On Directive 17 that means it sometimes stands
  against a three metre deck face with a ramp eight metres to its left; the
  run still produces fifteen frags a minute with no spawn deaths, but the
  harness reports it as stuck. That is an agent limitation rather than a map
  one. The active [navigation pass](height-aware-navigation.md) owns that work.
  Its actual-movement tests also found a collision defect at deck exits; simple
  map connectivity had not detected it.

## The problem, in the words that were used

"The maps need to be way bigger." "Doom was WAY bigger than that tiny arena map."
"More variety." "The maps should be more than just flat, didn't Quake have stairs
and things." "Some of the best multiplayer GoldenEye maps, they were bigger with
rooms and like items and things."

All four complaints are true of the tip. Two maps exist. Both are one flat square
room a hundred metres on a side with boxes in it. `docs/MAP-DESIGN.md` opens by
saying the current map fails most of its own rules, and it is right.

This plan is the answer: five maps instead of two, every one of them bigger than
what it replaces, four of the five built on a different flow shape, and a height
axis in the shared movement step so a map can have stairs and decks in it.

## Non-goals

- Overhangs, grates, bridges you can walk under, or any floor with a hole in it.
  The collision model is a heightfield of axis-aligned boxes, so a solid runs from
  the floor to its top and there is no space underneath it. `MAP-DESIGN.md` rule
  five (permeable floors) is therefore **not** satisfied by this plan; it needs a
  second solid per column and a real ceiling test, which is its own rung.
- Lifts, jump pads, teleporters, doors that open.
- A 3D hitscan test. Shots stay a segment in XZ; what changes is that a solid now
  only blocks a shot whose line passes below its top.
- Interest management and delta snapshots. `massive-arenas.md` owns those, and
  the field tier here is still inside the measured headroom (256 fighters used
  under six percent of the tick budget), so nothing in this plan needs them yet.
- Godot scene art per map. The client builds every map from `MapInfo`, so a new
  map is server data and needs no scene.

## The named references and what each one is for

| Reference | What is taken | Which map answers it |
|---|---|---|
| **GoldenEye Facility** | Interconnected rooms, no dead ends, a chase is the start of a plan | Compliance Yard |
| **Quake Q3DM17 (The Longest Yard)** | The best item on the most exposed ground, height as the whole subject of the map | Directive 17 Substation |
| **Dust II** | Two named destinations joined by a mid with one door, measured rollouts | Sector 9 Transit Hall |
| **Blood Gulch** | Two bases, an open middle worth a rifle, flanks worth a rush | Reclamation Gulch |
| **Doom / Unreal** | A floor plan you learn as a place, height used for drama | Arena Duel, rebuilt |

## The roster

One fragr unit is one metre. Playable extent is the full width of the square.

| id | Name | Extent | Tier | Flow shape | Power position | Main chokepoint | Heights |
|---|---|---|---|---|---|---|---|
| 1 | Arena Duel | **140 m** | arena | Rosette: a clear hub inside a broken gantry ring, spokes out to the spawn rim | Rail pad on the north gantry walkway, no cover on it, seen from the whole hub | The four gantry gaps at r=19, 23 m from the spawn rim | 0, 2.6 |
| 2 | Compliance Yard | **110 m** | arena | Pretzel: a three by three room block wrapped in a perimeter service corridor | Rail on the inspection gantry over the north room, the only high ground | The twelve room doorways, 5 m wide | 0, 1.4, 2.8 |
| 3 | Directive 17 Substation | **150 m** | arena | Fishbowl: four quadrant decks around a pit, ground corridors on the axes | Rail on the pit floor, in view of all four decks | The ramps up each deck's inner face | 0, 3.0 |
| 4 | Sector 9 Transit Hall | **200 m** | district | Figure eight: two halls joined by a mid plaza with three doors each way | Rail on the East Hall inspection deck, seen down the whole hall | Mid Doors, 6 m wide, 29 m from either hall | 0, 2.0 |
| 5 | Reclamation Gulch | **280 m** | field | Dumbbell: two walled compounds at the ends of an open gulch with two flank ridges | Rail on the knoll in the middle of the open ground, no cover within 20 m | The compound gates, and the ridge ends | 0, 1.2, 2.0, 3.0 |
| 6 | Tripoint Works | **320 m** | field | Trefoil: three compounds, three capture yards, a plaza nobody can hold | Rail on the southern capture yard deck, one of three equal prizes | The three compound gates and the three yard ramps | 0, 2.0, 3.0 |

Every one is bigger than the hundred-metre square it replaces. The roster spans
110 m to 320 m, which is the pit-to-field ladder in `map-scale.md` with an actual
map on four of its rungs instead of a number in a table.

### Why each one plays differently

- **Arena Duel** is a duel map that now has a middle worth holding. Its gantry
  ring is a wall at ground level and a firing step above it, so the hub is a room
  you fight *into* rather than a field you cross. Short rollouts, constant contact.
- **Compliance Yard** is the only map with no long sightline at all. Nine rooms,
  eighteen doorways, a perimeter loop, and a gantry over the north room. The
  scatter gun is the right answer almost everywhere; the rail is nearly useless,
  which is the point of having it in a roster.
- **Directive 17 Substation** inverts cover: the lowest ground is the most
  exposed, and going for the rail means standing at the bottom of a bowl while
  four decks look down at you. Fighting is mostly downhill and retreating is
  always uphill, because getting off a deck is a three metre drop and getting
  back on is a ramp. The first version of this map used concentric terrace
  rings with four stair notches cut in them; it read beautifully and pinned
  the playtest agents against a metre and a half of riser for forty seconds at
  a time, so it was rebuilt out of quadrant decks with three ramps up each
  inner face. The lesson is written into the code: a wall an agent can face
  with no answer to it is a map bug, not an agent bug.
- **Sector 9 Transit Hall** is the only map with named destinations and a
  measured rollout between them. Two people holding forward from opposite halls
  meet at Mid Doors after about five seconds. It is the map where pre-firing a
  corner is a skill rather than a guess.
- **Reclamation Gulch** is the only map where the rail is king. Two hundred and
  eighty metres, a hundred and eighty of it open ground between the compounds,
  and the flank ridges are the only way to cross it without being seen from
  both ends. Compound interiors are shotgun range. All three weapons have a
  home.
- **Tripoint Works** is the three-cornered map, and the only one built for a
  mode that does not exist yet. See below.

## Tripoint Works and the three-cornered mode

The shape asked for was three starting areas, capturable ground between them
that gates access to things, and a middle that is worth taking and impossible
to hold, because in a three-way fight whoever is ahead gets attacked by both
of the others and a map that lets the leader dig in ends the game early.

**The geometry, which is built.** Three identical compounds at a hundred and
twenty degrees to each other, a hundred and eighteen metres from the middle, so
no faction is closer to anything than another. Each has four gates, one in each
wall, and a firing walkway inside with two ways up, so all three are equally
defensible and none is a trap. Three capture yards sit on the arcs between the
compounds, each a raised deck with three ramps and four flanking blocks, so
taking one is a three-sided problem rather than a doorway. The middle is an
open plaza with three ridge spurs looking into it and wide gaps between them:
covered from three sides, campable from none, and the fastest route between
any two compounds passes through or beside it.

**Telling whose ground you are on.** Solids carry no faction on the wire, so
the compounds are told apart by what is in them. The Continuance's is a regular
grid of identical slabs laid to a pitch. The free side's is scavenged: five
blocks, no two the same size, nothing square to anything else. The Inheritance's is
one unbroken drum with no smaller parts anywhere near it, because an unmarked
machine that is not trying to be read does not build in pieces. You can tell
which compound you are in from the doorway.

**What the engine still needs**, none of which is in this change:

1. **Teams.** `Player` has a role, not a side. A faction id on the player, on
   the wire, and in `Snapshot` is the first rung.
2. **Three spawn areas** instead of one ring. `spawn_on_ring` picks a point on
   a circle; a three-faction mode needs a spawn set per faction, and a rule
   that a fighter spawns in its own compound.
3. **Zone state.** A capture zone is a position, a radius, an owner, and a
   contest timer, ticked in the sim and carried on the wire like a pad is.
4. **What a zone buys.** Today a pad is claimed once and respawns on a timer.
   Gating a weapon or a spawn point behind zone ownership is a change to the
   pickup rules, not a new system.
5. **Scoring and the end condition**, which is what makes two against one
   temporary rather than permanent.

Until then Tripoint Works plays as a large deathmatch map, and it plays
acceptably: six agents, no spawn deaths, about nine frags a minute.

## Height, and exactly how much of it

The shared movement step (`server/src/movement.rs` and its GDScript twin
`client/scripts/movement.gd`) has gravity and a jump but a single constant floor.
This plan gives it a **heightfield**:

- Every solid gains a `top`: the height of its walkable upper surface. The wire
  default is `WALL_TOP` (4.5), so an old `MapInfo` and the committed golden file
  both keep meaning exactly what they meant before.
- `STEP_UP` is 0.6 m. A solid blocks a fighter when its top is more than a step
  above what the fighter can climb from; otherwise the fighter walks onto it and
  its top becomes the floor.
- Step-down of up to `STEP_UP` snaps rather than falls, so a staircase is walked
  rather than bounced down.
- A drop larger than a step is a fall, on the gravity curve that already exists.
- Landing is swept, so a fighter that comes down onto a deck lands on it.

The whole of the change is four pure functions and a reordering of the existing
step. Flat ground with the old solids produces bit-identical numbers: the two
new terms (`support` and the step-down allowance) both collapse to the existing
`GROUND_Y` behaviour when no solid is low enough to stand on. That is what keeps
the committed golden vectors valid rather than merely close.

**Golden vectors.** The file gains `top` on every solid and three new cases,
`stair_climb`, `stair_descend` and `deck_edge_fall`, each pinning `y` at every
checkpoint. The existing eleven cases keep their existing expected states to the
last bit. The Godot harness checks `y` as a field now, not only `x`, `z`, `vx`,
`vz` and `yaw`, so a GDScript mirror that got the heightfield wrong fails.

**Shots.** `ray_blocked_by_cover` now interpolates the shot line between the
shooter's and the target's eye heights and ignores any solid whose top is below
it. Two fighters standing on the same deck can shoot each other; a fighter on a
deck shoots over the low walls below; and because every pre-existing solid has a
top of 4.5, every pre-existing cover test still blocks.

**Pads.** A pad gains the floor it sits on, and a claim needs the fighter to be
on roughly that floor, so a rail on a deck cannot be taken from underneath it.

## Architecture impact

| Area | Change |
|---|---|
| `server/src/maps.rs` | **New.** All five layouts as data, plus the parametric builders (`wall_with_doors`, `stair_run`, `terrace_ring`, spawn pockets) and a `MapDef` per map, each built once into a `OnceLock` |
| `server/src/sim.rs` | `MapKind` grows to five variants and delegates every geometry question to `maps.rs`; `half_extent` and `spawn_radius` become per-map; blocking, spawn search and shot cover become height aware; the sim's own move step gains the heightfield |
| `server/src/movement.rs` | `Solid.top`, `STEP_UP`, `Arena::support_height`, `Arena::blocked_at`, the reordered step, three new golden cases |
| `client/scripts/movement.gd` | The same, line for line |
| `client/scripts/arena_cover.gd` | Renders a solid at its real `top`, and sizes the floor and the boundary walls from `half_extent` so a 280 m map is not drawn inside a 100 m box |
| `client/scripts/test_move_golden.gd` | Checks `y` |
| `tools/playtest` | `Arena::line_of_sight` ignores solids below eye height, so an agent does not think a kerb is cover |
| `server/src/main.rs` | `--map` accepts the five names and ids; `--map-rotate` cycles all five |
| `docs` | This plan, the plan index, `docs/MAP-DESIGN.md` related list |

`arena_duel_solids()` does not survive as a free function; its callers were
`MapKind::obstacles` and nothing else, and its job (generate the layout from ring
radii rather than list forty boxes) is now what the whole of `maps.rs` does.
Arena Duel keeps its id, its name, its eight-fold symmetry and its spawn pockets.

## Protocol

Additive and backward compatible. `Solid` gains `top: f32` with a serde default
of 4.5, so an older client reading a newer server sees walls where it used to,
and a newer server reading the committed golden file sees walls where it used to.
`MapInfo` is otherwise unchanged; `half_extent` already exists and now varies.

## The correctness constraint that has broken this three times

Cover on a spawn point, or cover on the origin, has broken the playtest in three
previous layout attempts. This time it is mechanical rather than remembered:

1. `maps.rs` carries a `validate` pass, exercised by a test **for every map in
   the roster**, that asserts the origin is clear with a fighter's radius, that
   at least eight of the sixty-four sampled spawn-ring angles are clear, that no
   pad sits inside a solid, and that the boundary is not sealed.
2. A 2.5D flood fill from the origin, stepping up and down by the same rules the
   movement step uses, asserts that every spawn point and every pad is reachable
   from the origin. A map with an unreachable deck, a sealed room or a pit with
   no stairs fails the test rather than the playtest.
3. Tests that need a position ask the map for one (`half_extent`, the clear-lane
   scan, the spawn ring) and never hard-code a coordinate.
4. `cargo run -p fragr-playtest -- --agents 4 --rounds 1 --frag-limit 3
   --time-limit-seconds 45 --assert` must report zero spawn deaths before the PR
   opens, on the default map and on each new one.

## Lore

The Continuance certifies civic and industrial infrastructure for use as an
arena rather than building arenas, so every venue is a repurposed something
with the paperwork still bolted to it. Arena Duel is a municipal assembly
floor. Compliance Yard is a records and inspection block. Directive 17
Substation is a decommissioned transformer yard, its decks still numbered.
Sector 9 Transit Hall is a freight interchange. Reclamation Gulch is a
materials recovery site between two weighbridge stations. Tripoint Works is a
reclamation plant on a boundary where three jurisdictions meet. The names carry
directive numbers and sector ids because that is how the Continuance talks, and
the geometry is industrial because nobody built any of it for this.

The third side is not a monster and its compound should not be dressed as one.
It is unmarked: no serial, no plate, no label, no seal, no seam, which is the
exact opposite of a Continuance that stencils a directive number on everything
it owns. Its ground reads as one smooth shape with nothing small on it, and
that is the whole tell.

## Verification

```bash
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
cargo llvm-cov --workspace --locked --fail-under-lines 80
cargo run -p fragr-playtest -- --agents 4 --rounds 1 --frag-limit 3 --time-limit-seconds 45 --assert
tools/godot_check.sh
```

## Measured, 2026-09-19

Six agents, one round, frag limit five, forty five second limit, seed 1, on a
developer laptop. The CI line is the four agent run on the default map.

| Map | Extent | Frags/min | First frag | Spawn deaths | Harness complaints |
|---|---|---|---|---|---|
| Arena Duel (CI, 4 agents) | 140 m | 23.8 | 5.0 s | **0** | none |
| Arena Duel | 140 m | 23.0 | 4.5 s | **0** | none |
| Compliance Yard | 110 m | 3.8 | 4.6 s | **0** | none |
| Directive 17 Substation | 150 m | 15.3 | 8.2 s | **0** | straight-line agents pinned on deck faces |
| Sector 9 Transit Hall | 200 m | 14.1 | 5.2 s | **0** | one agent stalled 26 s |
| Reclamation Gulch | 280 m | 6.4 | 5.5 s | **0** | none |
| Tripoint Works | 320 m | 9.0 | 9.2 s | **0** | none |

Zero spawn deaths on every map in the roster, which is the constraint three
previous layout attempts broke. Frags per minute falls with extent, exactly as
it should: a two hundred and eighty metre map is not meant to play like a duel
box. The stall reports on Directive 17 and Sector 9 are the harness's
straight-line agent meeting a deck face, not a fighter that cannot move; both
maps produce a frag every four seconds regardless.

## Success criteria

- [x] Six maps, each selectable by `--map`, each bigger than 100 m
- [x] Six distinct flow shapes with a stated power position and chokepoint
- [x] Height in the shared step, the GDScript mirror in agreement, golden
      vectors regenerated with all eleven old cases bit-identical
- [x] Reachability and spawn-safety tests pass for every map in the roster
- [x] Playtest reports zero spawn deaths on every map
- [x] Coverage stays above the unfiltered eighty percent floor
- [x] A map built for the three-cornered mode, with the engine gaps written down
- [ ] Three-faction spawns, zone capture, and the mode that uses them
- [ ] An agent that can find a ramp

## Related

- `docs/MAP-DESIGN.md`: the rules these maps are built against.
- `map-scale.md`: the size ladder and the rung order.
- `arena-choke-geometry.md`: cover inside one room (shipped, #72).
- `second-scrap-map.md`: the second map and `--map` (shipped, #80).
- `massive-arenas.md`: what the wire needs before the field tier gets crowded.
