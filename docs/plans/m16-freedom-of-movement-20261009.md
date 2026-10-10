# Freedom of Movement development avenue

Status: **in flight**, 2026-10-09. Spend: $0. This is the first graybox for
accepted level 16, not a connected mission and not the motorcycle lesson.

## Lore route

The accepted route is in [Level 16](../CAMPAIGN-MISSIONS.md) and
[Freedom of Movement](../campaign/l16-freedom-of-movement.md). Episode IV,
the ceremonial avenue from the sanctioned-games stadium to the Forever Office.
Regional uprisings are already breaking enforcement. The coalition needs a
foothold at the Office before dawn. The Union built this road for its parades.
People now come along it. The new lesson in [CAMPAIGN.md](../CAMPAIGN.md) is
the Motorcycle. That vehicle does not exist. Level 16 has no door. The Office
chamber doors belong to level 17.

The documented shape, kept and not retold:

1. Arrival at the ceremonial gate and the plaza. The Office is the far end.
2. The first stretch: a barricade across the road and one Notary.
3. Checkpoints, with Clerks, a Turret at a parade stand, and narrower side
   alleys around the barriers.
4. The transit pocket: a bus and two Clerks. Freeing anyone there is not built.
5. The turn is spatial. The same parade road is the way people approach the
   Office. No line of dialogue says so.
6. The forecourt is two-sided. The documented fight is dismounted: Enforcers
   at the entrance, Turrets at the portico, a Heavy Sweeper, and an Assessor
   over the fountain.
7. The exit of this level is the foothold at the closed chamber doors.

The green wave, Mara's line, Latch riding pillion, street screens, allies
holding the left flank, and the prisoners on the bus stay in that text. This
pass does not stage them.

## Graybox

`server/maps/test/m16_freedom_development.json` is a version 1 discovery map.
Map id 1016. Name: Freedom of Movement (development). It has no mission key,
no `m13` key, and no vehicle list. `server/tests/m16_development.rs` loads it
through `AuthoredMap::read` and checks map id 1016, an empty campaign mission,
and the landmarks.

On foot only. The player stands at `ride_start` on the gate plaza, facing the
Office. A wide concrete avenue runs east between repeated steel posts and
issued enamel blocks. Two barriers cross the center and stay walkable at
either end. Three side pockets open off that road: `side_pocket_barricade`
and `side_pocket_checkpoint` on the north, `side_pocket_transit` on the south.
The south pocket holds the bus shape and two Clerks. The north checkpoint
holds the parade stand, a Turret, and a Clerk. The avenue then opens into a
forecourt with cover on both flanks, a fountain, and `forecourt` in front of
it. `office_threshold` is the foothold before a closed door slab and the
Office face. There is no passage into the Office.

Encounters use only current kinds: Notary, Clerk, Turret, Enforcer,
Heavy Sweeper, and Assessor. Supplies use current grants: Pistol, Rifle,
Shotgun, and Rocket, plus contested armor, a medkit, Shells, and Bullets.
The fountain cache and the kiosk stock are optional secrets already named in
the level text. Static strip lights and Union seals are repeated manufacture,
not the green wave.

The road is the crowd's approach. It is wide, axial, and open from the gate
to the Office, with side mouths joining it. No new actor stands in for the
people, the allies, or the prisoners.

## Unbuilt

- Motorcycle, jetpack, and any new vehicle kind. No bike is parked at the gate.
- Connected mission, campaign id, save, continue, and menu entry.
- The green wave, traffic-light schedule, and the line that it was not the coalition.
- Rooftop grandstand jump. Cells on that landing are not placed at ground level
  as a substitute.
- Level 17's chamber doors, interior, and Denial.
- Ally flank holders, bus prisoners, and a crowd. Those are not current actors.
- Fresh-player time, par, and the review gate as accepted appearance. The
  graybox only makes the road readable as geometry.

Verification for this pass is `cargo fmt -p fragr-server` and
`cargo test -p fragr-server --locked --test m16_development -- --test-threads=1`.
A passing load is not a finished level 16.
