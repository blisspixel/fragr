# Authoritative vertical aim

Status: proven, [PR #170](https://github.com/blisspixel/fragr/pull/170),
[v0.19.0](https://github.com/blisspixel/fragr/releases/tag/v0.19.0) (2026-09-19).
Branch: `feat/vertical-aim`. Spend: $0.

## Problem and scope

Camera pitch is local only. The server shoots a horizontal ray, accepts targets
regardless of elevation, then bends its cover check toward each target's height.
This makes looking above or below a fighter irrelevant and misrepresents combat
on the existing elevated maps. Spectator eye views also omit the fighter's pitch.

Deliver one complete vertical aim path through human input, agent actions, server
combat, snapshots, and spectator presentation. Preserve server authority, current
weapons, movement, map geometry, and transport. This is not headshots, projectile
weapons, a weapon rebalance, prediction, or completed campaign content.

## Contract and implementation

- Add optional absolute `Action.pitch`, radians positive upward. Finite values
  are clamped to 85 degrees in either direction. Missing values retain the last
  pitch, initially zero. Spawn/respawn resets pitch. Publish pitch in snapshots
  and input acknowledgements, with deserialization defaults for older recordings.
- Extend `look_at` with optional world `y`. A player target aims at its body;
  legacy x/z targets without y aim horizontally. Apply target intent after
  movement, preserving the existing precedence over absolute facing. Invalid
  coordinates cannot produce nonfinite state. Update MCP schemas and validation.
- Use one unit 3D shot ray from the authoritative eye height, with deterministic
  dispersion in the weapon cone. Intersect finite fighter cylinders, radius
  0.5 and height 1.8 world units above their feet. Choose the nearest positive
  surface intersection within weapon range. Cover uses the same ray against
  solid volumes from ground to their authored top, including descending shots
  that enter above a solid and hit its top farther along.
- Put reusable intersection/aim math in `server/src/combat.rs`; `sim.rs` retains
  outcome ownership. No new dependency or parallel simulation. Rule bots receive
  vertical target intent without replacing their horizontal turning behavior.
- Reuse that same solid intersection for playtest agents' sight checks, replacing
  the duplicated flat-ray implementation. Their visibility follows actual fighter
  height and the body-centre target used by `look_at`.
- Extend the existing client action builder, pawn state, and camera seam. Human
  pitch remains responsive locally between snapshots. Spectators reconstruct the
  selected fighter's pitch. Keep yaw conversion in `ServerYaw` and test the actual
  camera basis against the server direction convention.

The server's old 1.5 m eye offset disagreed with the client's 1.6 m offset. Both
now use 1.6 m, and the eye camera no longer sits 0.15 m ahead of its shot origin.
Scatter falloff uses traveled distance to the cylinder surface; a target centred
five metres away is reached near 4.5 m, so that regression fixture deals 38 rather
than 37 damage. The damage table itself is unchanged. Two seeded dispersion draws
per shot intentionally change old simulation results; old recordings remain
readable rather than promising identical replay from old seeds.

Repeated trace tests found a separate tie bug: the next round's previous winner
used unordered score iteration. Round end and round start now share the same
score-descending, callsign-ascending ranking, tested across roster orders.

Visual inspection also found that the scatter reticle's nominal ring was an
opaque filled rectangle drawn over its crossbars. Remove the unused filled
layers, retain the wider outlined cross, and draw all dark bar edges behind
the coloured parts. The target stays visible and the selected reticle colour
applies consistently.

## Research

Checked 2026-09-19: the primary references for
[ray/slab intervals](https://pbr-book.org/4ed/Shapes/Basic_Shape_Interface) and
[finite cylinder intersections](https://pbr-book.org/4ed/Shapes/Cylinders) describe
the geometry and parallel-ray/boundary concerns. Implement compact local math
with exact regression cases, using the established server coordinate system.
[Godot Node3D](https://docs.godotengine.org/en/stable/classes/class_node3d.html)
documents the camera transform basis. Retain the pinned Godot/Rust stack.

## Acceptance

- [x] Looking above/below a fighter misses; correctly aimed elevated shots hit.
- [x] Upward/downward cover, solid-top crossings, range, nearest target, and
  near-parallel intersections have deterministic tests.
- [x] Nonfinite input is contained; old actions and recordings remain readable.
- [x] Rule bots, MCP, scripted agents, and the decision controller remain viable.
- [x] Human pitch survives snapshots and eye spectators reproduce it.
- [x] Workspace gates, 90 percent unfiltered coverage, Godot checks, CPU repeat
  benchmark, real-wire playtests, and inspected visual tours pass.
- [x] Protocol, adapter guidance, roadmap, and this plan reflect tested behavior.

## Local evidence (2026-09-19)

Windows 11, Ryzen 7 7840U, Radeon 780M, Rust 1.98.1, Godot 4.7.2-stable.
Source: this branch on parent `1ae55df`. Integration history identifies the final
reviewed commit. No paid calls.
All five CI jobs passed on Linux, Windows, and macOS before squash integration
at `e481039`.

- 575 workspace tests pass; one existing vector-regeneration test is ignored.
  Unfiltered workspace line coverage is 95.17 percent. Format, warnings-denied
  Clippy, release build, and dependency license/bans/source checks pass.
- Thirteen Godot harnesses pass, including real action-builder pitch forwarding,
  camera basis, human aim ownership, and spectator pitch. Real-wire captures
  observe camera pitch +/-0.400000006 and server pitch +/-0.4.
- Both final 20-state renderer tours pass and their contact sheets were inspected:
  OpenGL 3.3 Compatibility and Vulkan 1.4 Forward+ on the Radeon 780M. Inspected
  full-size upward/downward views confirm the repaired reticle. Eight published
  README stills come from `.agents/qa/vertical-final`; the alternate renderer is
  in `.agents/qa/vertical-final-vulkan`. No other GPU vendor is claimed.
- Four real-wire reflex agents complete a round in 26.45 s: ten frags, first frag
  at 5.05 s, longest gap 10.7 s, zero spawn deaths. Frustration assertions pass.
- A separate local decision controller receives 600 snapshots and sends 599
  actions in 30 s, makes 89 local decisions, and scores three frags without dying.
  The scripted adapter also scores a frag and defeats the drone in that session.
  Remote calls and run spend are zero.
- The pre-pitch v0.16 trace still verifies its original exact-byte SHA-256.

Serial offline CPU runs, seed 42, 12,000 ticks plus a complete repeat per row.
No renderer ran beside these measurements. These are session plus encoding
measurements, not network capacity, GPU results, or comparative speedup claims.
The configured bot count excludes the transient mid-round drone.

| Bots | Map | Session p99 ms | Encode p99 ms | Total p99 ms | Maximum ms | At/over 50 ms | Trace repeats |
|---|---|---:|---:|---:|---:|---:|---|
| 16 | Arena Duel | 0.017407 | 0.009215 | 0.024575 | 0.1989 | 0 | yes |
| 64 | Reclamation Gulch | 0.061439 | 0.026623 | 0.081919 | 0.6743 | 0 | yes |
| 128 | Tripoint Works | 0.147455 | 0.055295 | 0.188415 | 1.3372 | 0 | yes |

Receipts live in `.agents/vertical-*.log`, `.agents/bench/vertical-*.json`,
`.agents/playtest/vertical.json`, and `.agents/vertical-brain.json`.

Review found an existing observation limitation: the playtest harness drops a
shot when its shooter dies in the same tick and disappears from that snapshot.
Its per-weapon kill attribution also reads the last observed loadout. The smoke
above proves round flow, not accuracy or weapon balance. Complete shot identity
and impact positions should be the next combat-feedback increment so effects
and measurement use the same authoritative evidence.
