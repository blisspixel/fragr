# Readable arsenal and explosives

Status: names and cycling shipped, 2026-09-22. v0.41.0 reads Pistol, Rifle,
Shotgun, and Railgun, and ammo pads read Bullets, Shells, and Cells. v0.42.0
walks those guns with the wheel, the bracket keys, and 1 through 5. Wire ids
for the five current weapons are unchanged. The sniper rifle, rocket launcher,
grenade, proximity mine, and remote mine are locked as campaign finds. None of
them is implemented.

## Goal

Use familiar weapon names. The opening kit stays fists, then the pistol and
the rifle. Shotgun and Railgun stay the close and long guns that already
exist. Add five earned weapons, found by playing the mission that teaches
them, not granted from a menu and not present in the arcade full arsenal:

| Player reads | Wire id, when added | Taught | What it must feel like |
|---|---|---|---|
| Sniper Rifle | `sniper` | M04 crater cut, after customs has already taught the Railgun | Slow, tight, high-damage hitscan. A scope is presentation. It is not a renamed rail beam. |
| Grenade | `grenade` | M03, on the ordinary route | Thrown arc, bounce, fuse, then blast. It does not explode on impact. |
| Proximity Mine | `proximity_mine` | M05, before the converging fight | Sticks to the first surface, arms after a visible delay, blinks, and detonates when a body enters the radius. |
| Remote Mine | `remote_mine` | M06, after proximity is already known | Sticks and waits. A separate detonator explodes the ones you own. Firing a gun does not set them off. |
| Rocket Launcher | `rocket` | M08, before the exterior crest | A flying rocket that explodes on impact. Splash falls off and stops at cover. |

GoldenEye is the reference for the grenade and the two mines: place them,
read the tell, and choose when the blast happens. Doom II is the reference
for the rocket launcher as the splash gun. The older proposal names Lobber
and proximity tin are this rocket launcher and this proximity mine. They are
not a second splash gun and a second mine.

## How you earn them

M01 still starts with fists and finds the pistol, then the rifle. These five
are not in that kit, not in a secret menu, and not on the six arcade maps.

Each one sits on the ordinary route of its teaching mission, with enough
ammunition to learn the new verb and a space that makes that verb the
interesting choice. Finishing the mission carries it into the next mission's
entry equipment once a run can cross missions. A continue restores that
mission's entry kit, so a death before leaving puts the found copy back on
the floor until you pick it up again. Quitting still ends the local run.
Disk saves do not exist yet, so there is no permanent account unlock.

None of the five is required to finish an earlier mission. The customs lane
in M04 still teaches the Railgun without a sniper. M03 still has no new
mandatory gun; the grenade is the new tool. The M08 walker stays defeatable
without the rocket launcher.

## Scope and architecture

Keep the current wire ids compatible. Display names stay in
`EquipmentState`. New ids are added with the weapon, not before a shot or a
blast exists.

The sniper uses the existing hitscan path: server aim, server hit, a tighter
cone, a slower cooldown, and higher damage than the rifle. Cells feed it, so
it spends the same scarce pool as the Railgun. The scope never decides a hit
on the client.

Rockets and grenades share one authoritative projectile: owner, velocity,
bounce or impact policy, fuse, and cleanup on hit, death, round, or mission
reset. Mines share one placed-device record with a trigger policy
(proximity or remote), an arming delay, a cap on live devices, and the same
cleanup. Blast damage is server-side, reduced by distance, and blocked by
solids. The owner can be hurt. The Godot client sends the throw, the place,
and the detonator, then draws the server's body and the tell.

Grenades, proximity mines, and remote mines carry their own counts. They do
not draw Bullets, Shells, or Cells. Rockets use a new `rockets` pool, shown
as Rockets. Remote detonation is its own action.

Bots do not need these weapons in the first implementation. Adding a weapon
grows the service-record array, which is five slots today, so the record
version moves in the same change as the new id.

## Verification

A sniper test proves a tight hit, a miss outside the cone, and that it does
not reuse Rail damage or the rail beam. Projectile tests cover flight,
bounce, fuse, impact, and cleanup. Mine tests cover stick, arming, proximity,
remote detonation, the live-device cap, owner damage, and a wall that stops
the blast. A death, a round end, and a mission reset remove both projectiles
and mines. Human and agent controls share the action. Update `docs/protocol.md`
and the adapter docs with the wire change. Inspect a tour only when a
playable mission actually contains the weapon.

## Spend and success

Local development is free. Viewmodels and blast audio wait until the
behavior is frozen, and paid generation stays behind the existing cap.
Success means each earned weapon is found where its mission brief says, plays
differently from the pistol, rifle, shotgun, and railgun, and is absent from
M01 and from arcade matches. No explosive or sniper shot is implemented yet.
