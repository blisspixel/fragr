# Readable arsenal and explosives

Status: names and cycling shipped, 2026-09-22. v0.41.0 reads Pistol, Rifle,
Shotgun, and Railgun, and ammo pads read Bullets, Shells, and Cells. v0.42.0
walks those guns with the wheel, the bracket keys, and 1 through 5. Wire ids
for the original guns are unchanged. The found Shiv is the sixth existing gun
slot. Counted grenades are implemented locally for level 5 through the
[grenade foundation](hand-grenade-foundation.md), separately from those gun
slots. The Proximity Mine is a counted device with its own `place_mine` action,
implemented on the [level 8 custody range](l08-custodian-of-record-prototype.md).
Sniper Rifle, Rocket Launcher and Remote Mine remain planned campaign finds.
The table below follows the accepted twenty-level
treatment, replacing this plan's historical ten-mission numbering.

Decided 2026-09-25: the campaign has no carry cap. Every gun found on the route
below stays carried, Doom style, all the way to the credits; nothing hits the
floor to make room for the next pickup. [WEAPONS.md](../WEAPONS.md)'s "you
carry a melee, a sidearm, and two found weapons" rule is an arcade and
multiplayer rule and does not apply here. [CAMPAIGN.md](../CAMPAIGN.md#combat-and-level-contract)
owns this carve-out for the campaign specifically.

## Goal

Use familiar weapon names. The opening kit stays fists, then the pistol and
the rifle. Shotgun and Railgun stay the close and long guns that already
exist. Add five earned weapons, found by playing the mission that teaches
them, not granted from a menu and not present in the arcade full arsenal:

| Player reads | Wire id, when added | Taught | What it must feel like |
|---|---|---|---|
| Sniper Rifle | `sniper`, planned | Level 7, Declared Goods, after customs teaches the Railgun | Slow, tight, high-damage hitscan. A scope is presentation. |
| Grenade | `throw_grenade` Action and `grenades` count | Level 5, No Forwarding Address, on the ordinary route | Thrown arc, bounce, forty-tick fuse, then covered falloff blast. |
| Proximity Mine | `place_mine` Action and `proximity_mines` count, development prototype | Level 8, Custodian of Record | Sticks, arms after a visible delay, blinks, then triggers on a body. |
| Remote Mine | `remote_mine`, planned | Level 11, Right of Search | Sticks and waits for its separate owner detonator. |
| Rocket Launcher | `rocket`, planned | Level 13, The Weight of Permission | Flying rocket, impact blast, falloff and solid occlusion. |

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
interesting choice. Finishing the mission carries it, and every earlier find,
into the next mission's entry equipment once a run can cross missions. Nothing
is dropped to make room: by the Martian foundry the player is carrying the
pistol, rifle, shotgun, railgun, sniper rifle and grenades at once, each with
its own ammunition pool. A continue restores that mission's entry kit, so a
death before leaving puts the found copy back on the floor until you pick it
up again. The local mission-entry save carries completed equipment and earlier
choices through levels 1 to 5; leaving retains that run. It provides no permanent
account unlock. Version 6 stores the grenade count independently, and strict
historical upgrades assign zero grenades with exact prior-byte archives.

None of the five is required to finish an earlier mission. The customs lane
in level 6 still teaches the Railgun without a sniper. Level 5 has no new
mandatory gun; the grenade is the new tool. The proposed later walker stays defeatable
without the rocket launcher.

## Scope and architecture

Keep the current wire ids compatible. Display names stay in
`EquipmentState`. New ids are added with the weapon, not before a shot or a
blast exists.

The sniper uses the existing hitscan path: server aim, server hit, a tighter
cone, a slower cooldown, and higher damage than the rifle. Cells feed it, so
it spends the same scarce pool as the Railgun. The scope never decides a hit
on the client.

Grenades use one bounded authoritative projectile with owner, velocity, contact
count and fixed fuse. Explicit leave removes owned devices, while a dead owner
retains committed throws. Round/map/mission resets clear them. Future rockets
may reuse its geometry helpers, with a separately validated impact policy.
Planned mines share one placed-device record with a trigger policy
(proximity or remote), an arming delay, a cap on live devices, and the same
cleanup. Blast damage is server-side, reduced by distance, and blocked by
solids. The owner can be hurt. The Godot client sends the throw, the place,
and the detonator, then draws the server's body and the tell.

Grenades, proximity mines, and remote mines carry their own counts. They do
not draw Bullets, Shells, or Cells. Rockets use a new `rockets` pool, shown
as Rockets. Remote detonation is its own action.

Agents can explicitly throw through the same Action and equipment controller.
Grenade records have a separate compatible default-zero counter, preserving the
six weapon slots and record version 1. A future new gun must extend and version its
own gun contract; no fake grenade gun slot is introduced.

## Verification

A sniper test proves a tight hit, a miss outside the cone, and that it does
not reuse Rail damage or the rail beam. Projectile tests cover flight,
bounce, fuse, impact, and cleanup. Mine tests cover stick, arming, proximity,
remote detonation, the live-device cap, owner damage, and a wall that stops
the blast. Existing grenade checks distinguish dead owners from explicit leave
and coherent resets. Human and agent controls share the action. Update `docs/protocol.md`
and the adapter docs with the wire change. Inspect a tour only when a
playable mission actually contains the weapon.

## Spend and success

Local development is free. Viewmodels and blast audio wait until the
behavior is frozen, and paid generation stays behind the existing cap.
Success means each earned weapon is found where its mission brief says, plays
differently from the pistol, rifle, shotgun, and railgun, and is absent from
M01 and from the default arcade kit. Grenade implementation evidence belongs
to its bounded foundation and M05 plans; the other four additions remain unbuilt.
