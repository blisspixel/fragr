# Campaign prototype captures

These dated images preserve specific development evidence. They are not the
README's current-build gallery or a claim that the campaign is complete.

The 2026-09-20 M01 captures show the first facility-detail pass on
`feat/m01-intake-encounter`, using the live server, ordinary walking and combat,
Godot 4.7.2, Windows and AMD Radeon 780M OpenGL. Source capture set:
`.agents/qa/m01-facility-final-gl/`, manifest `client/qa/m01-facility.json`.
The companion Vulkan run was inspected separately.

- `m01-annex-20260920.png`: safe property-intake arrival and original Union marker.
- `m01-facility-20260920.png`: twelve views covering signs, lockers, both stair
  routes, records, service machinery and the lift.

In those facility captures only three introductory enemies were authored.
Objectives, interactive terminals and extraction were unbuilt. See the
[facility plan](../../plans/m01-facility-detail.md) for scope and verification.

The later mission-sequence captures, also dated 2026-09-20, use the same host
and engine with `.agents/qa/m01-mission-release/` as their source:

- `m01-transfer-20260920.png`: the visible transfer console and live Use prompt.
- `m01-mission-20260920.png`: sixteen states covering combat, the closed gate,
  record discovery, opened route and server-confirmed prototype departure.

The short F presses change actual mission state. A separate Vulkan run also
passed and was inspected. The [sequence plan](../../plans/m01-mission-sequence.md)
records shared-party and agent evidence. The full mission population, opening,
secrets, checkpoints, final art and M02 remain unfinished.

The 2026-09-27 M02 stair-top graybox captures use a live human session on Godot
4.7.2, Windows and AMD Radeon 780M OpenGL. Source capture set:
`.agents/qa/m02-stair-asserted/`, manifest `client/qa/m02-graybox.json`.

- `m02-shotgun-before-claim-20260927.png`: the Shotgun visible ahead of the
  player on the upper gallery before it is claimed.
- `m02-seated-guard-room-20260927.png`: two idle Clerks behind a table before
  the first encounter wakes.
- `m02-service-stair-20260927.png`: the descent after the first fight.

These frames establish the order and graybox cues, not a finished room or
fresh-player acceptance. The opening ward tableau and Latch are still absent.
See the [stair-top plan](../../plans/m02-guard-room-at-stair-top.md).
