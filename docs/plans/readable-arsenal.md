# Readable arsenal and explosives

Status: names in the HUD, 2026-09-22. Pistol, Rifle, Shotgun, and Railgun are
what the player reads. Wire ids are unchanged. The sniper, grenades, and mines
in this plan are still unbuilt.

## Goal

Use familiar weapon names and roles. Replace player-facing Tack, Flechette and
Scatter labels with Pistol, Rifle and Shotgun; call Rail a Railgun. Add a distinct
Sniper Rifle, hand grenades, proximity mines and remote mines. GoldenEye-style
mine placement and deliberate remote detonation are the requested reference.

## Scope and architecture

Keep current wire IDs compatible during the naming change. Centralize display
names across HUD, pickups, records, agent descriptions and docs. Add original
weapon appearance and audio through the existing asset pipeline. The sniper
needs its own precision/aiming role; it is not proved by relabeling a rail beam.

Explosives use one Rust authoritative projectile/placed-device seam: owner,
throw trajectory, fuse or arming time, trigger policy, cover-aware blast damage,
bounded live-device counts, cleanup on death/round/mission reset and snapshot
presentation. The Godot client supplies intent and displays server facts.
Inventory, ammo, friendly-fire rules and bot use need explicit balance decisions.
No new projectile damage or mine authority belongs in the client.

## Verification

Tests cover throw/impact/fuse, arming, proximity and remote triggers, ownership,
wall shielding, trades, death/reset cleanup and inventory accounting. Verify
human and agent controls, update the protocol and adapter docs together, run
the full repository checks and inspect a refreshed visual tour with motion.

## Spend and success

Local development is free. Paid art/audio retains the repository's separate
quota and approval gates. Success means readable names everywhere and distinct,
tested sniper/grenade/mine play. No mechanic in this plan is claimed implemented.
