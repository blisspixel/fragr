# Launch Authority connected first pass

Status: **in flight**, 2026-10-09. Spend: $0. This pass stays on the development
battlefield `server/maps/test/launch_authority_development.json`. It is not a
mission, a save stage, or a menu entry. The accepted route is the
[level 14 brief](../campaign/l14-launch-authority.md): depot, bermed approach,
gantry sightline, open circuit, and sheltered infantry trenches. The jeep
capture at the depot remains the vehicle lesson. Infantry can still finish
without it. No escort and no vehicle timer.

## What the development map already had

Before this pass, `tools/author_launch_authority.gd` reproduced the committed
file byte for byte (38568 bytes, LF). Map id 1014 and the name Launch Authority
(development) were already set. `server/maps/test/custody-range.json` also uses
1014 and was not touched. The file had no mission document and no
`campaign_mission_id`.

The battlefield already contained:

- Freight-lift arrival, with a tested gantry sightline from the lift
  `[-46, 3.6, -52]` to the frame at `[5, 27, 41]`.
- Depot defense on foot: clerks behind the sandbags, sweepers by the vehicle
  sheds, and a turret on the depot roof. Ordered group `depot_defense`.
- The captured jeep under the motor-pool cover, the parked Notary gunner
  lesson, and the repair bay's medkit and armor.
- The bermed approach: west, east, and center berms, two midfield bunkers,
  berm clerks, one ranged sweeper on the marksman plinth, and the bend turret.
  Ordered group `berm_watch`.
- An open outer circuit of thirteen `circuit_*` landmarks. The jeep drives
  that road. Nothing on it has to be unlocked.
- Supplied infantry flanks, apron resupply outside the gantry trigger, and the
  gantry control squad. Five ordered groups, twenty existing enemies, twenty
  finite supplies, and 119 solids.
- An infantry clear that already proves the same groups with the jeep present,
  absent, and destroyed. The driver never takes a seat.

The QA route names the open flank lanes as trenches. Those lanes run beside
the berms and through the midfield bunkers. They were not a sheltered cut
through the middle of the field.

## What this pass added

Ten concrete parapets, top 1.75 m, so a standing eye at 1.6 m is covered and
the lane is not a roof. The walkable cut is centered at x=0.5. It starts at
the south mouth `[0.5, 0, 5.5]`, north of the existing berm-watch cover, and
ends at the north mouth `[0.5, 0, 23.5]`, short of the z=25 crossing and the
z=27 resupply road. Those crossings, the flank lanes, and the outer circuit
stay open.

| Solid | Bounds (min to max) |
| --- | --- |
| `trench_west_00` | x=-0.75 to -0.25, y=0 to 1.75, z=6.25 to 15 |
| `trench_west_01` | x=-0.75 to -0.25, y=0 to 1.75, z=17.5 to 22.25 |
| `trench_east_00` | x=1.25 to 1.75, y=0 to 1.75, z=6.25 to 8 |
| `trench_east_01` | x=1.25 to 1.75, y=0 to 1.75, z=10.5 to 22.25 |
| `trench_bunker_west_south` | x=-4.25 to -0.75, y=0 to 1.75, z=14.5 to 15 |
| `trench_bunker_west_north` | x=-4.25 to -0.75, y=0 to 1.75, z=17.5 to 18 |
| `trench_bunker_west_back` | x=-4.25 to -3.75, y=0 to 1.75, z=14.5 to 18 |
| `trench_bunker_east_south` | x=1.75 to 5, y=0 to 1.75, z=7.5 to 8 |
| `trench_bunker_east_north` | x=1.75 to 5, y=0 to 1.75, z=10.5 to 11 |
| `trench_bunker_east_back` | x=4.5 to 5, y=0 to 1.75, z=7.5 to 11 |

The west bunker opens east into the parapet gap. It holds contested
`trench_west_bullets` (80) at `[-2.5, 0, 16.5]`. The east bunker opens west
into its gap. It holds contested `trench_east_medkit` (50) at `[3.5, 0, 9.5]`.
Landmarks `trench_south_mouth`, `trench_lane`, `trench_bunker_west`,
`trench_bunker_east`, and `trench_north_mouth` mark the cut. No new encounter
and no new enemy kind. The helper now writes 129 solids, 22 supplies, and the
same 20 guards. Regenerated JSON is LF.

## What stays unbuilt

- Continuance Walker: no AI, phase, stomp ring, artillery lane, relocation, or
  new actor kind. Supporting squads from the pad road and gantry stay out.
- Voiced departure: Mara's site calls, Tern's pad line, the page in, and the
  page out. Other-site flares stay out.
- Episode completion. The gantry control room is a development destination,
  not a fleet lift.
- Mission identity: no MissionId, `campaign_mission_id`, save promotion, or
  menu launch. Map id 1014 is unchanged.
- Extra ranged sweepers on the berm crests. The existing berm watch keeps its
  one plinth marksman and the bend turret.
- The trench-bunker secret (rockets and cells at a firing slit) and the gantry
  ledge armor jump. `gantry_armor` and `east_flank_cells` remain the stocks
  already on the map.
- Motorcycle, jetpack, a required escort, and a vehicle timer.

## Verification

`cargo fmt -p fragr-server` ran first.

`cargo test -p fragr-server --locked launch_authority -- --test-threads=1`
passed 3 tests in the server library (exit 0, 5.57s): the static fleet and
route gate, the driven outer circuit, and the infantry clear with the jeep
present, absent, and destroyed. The static gate now also requires foot routes
to the five trench landmarks, shelter from standing fire on both sides of the
parapet, an open lane, and clear crossings at z=25 and z=27. Depot and berm
enemy kinds stay the existing clerks, sweepers, ranged sweeper, and turrets.

Fresh-player review, final Mars art, a played Walker, and campaign completion
are not claimed.
