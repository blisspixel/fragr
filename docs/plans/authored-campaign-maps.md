# Authored campaign map data

**Status:** implemented and locally verified, 2026-09-19. Integration record:
[#177](https://github.com/blisspixel/fragr/pull/177). Follows
[finite-volume geometry](campaign-spaces.md), shipped in #176.
**Goal:** load and play M01's intake annex from validated local JSON through the
normal server, human client, agents and spectators. Spend: $0.

## Product boundary

[M01's brief](../campaign/m01-recall-notice.md) owns the route, story and cast.
Build its service street, confiscation bay, intake hall, records balcony,
maintenance flank, transfer office and lift in that order. Keep both approaches
to the balcony, the return view into the hall and a recognizable lift landmark.
Latch is located through transfer records here and rescued in M02. No early
Inheritance message, radio-dependent objective or giant empty arrival field.

The first pass is an explicitly labeled traversal blockout. It does not stand in
for the complete mission. Inventory, authored encounters, interaction, extraction,
checkpoint state, localization and production art follow through their own seams.
Do not silently put arena scoring, ring spawns or a center-spawned boss into the
campaign. Keep the existing six-map arcade roster available and unchanged.

## Runtime and content contract

- Keep Rust and the existing Serde stack. A versioned local map document contains
  stable identity, bounds, canonical solid volumes, explicit three-dimensional
  spawn points, named route landmarks and bounded presentation identifiers.
  Read a capped byte stream before parsing; reject unsupported versions, duplicate
  identities, unknown fields, invalid bounds and excessive content before binding.
- Reuse `movement::Solid` and geometry validation. Do not reintroduce a second
  collision shape or a client-only ceiling. Keep presentation outside collision
  data, with an explicit association to a solid. Use bounded enums or registered
  IDs for surface kits; map files must not select arbitrary files or URLs.
- Prepare immutable map data and navigation together before readiness. Introduce
  one runtime map handle through `GameState` and `GameSession`, with built-in maps
  and loaded content using that same path. Audit movement, shots, spawn selection,
  pickups, bot queries, snapshots, `MapInfo`, rotation and benchmark initialization.
  An optional second geometry override that leaves those callers on different
  maps is not an acceptable shortcut.
- Campaign spawns are feet positions with full body clearance and real support,
  including floors beneath ceilings. Never select the highest roof at an XZ
  position. Reuse the existing cover/clearance ranking where respawns are allowed;
  preserve legacy candidate order and seeded traces for the arcade roster.
- Reject unsupported combinations at startup, such as a single custom mission
  file with arcade rotation or Episode 0's arena objectives. Ordinary loopback
  and LAN hosting require no account or provider. Host files are authoritative;
  clients receive validated state, not filesystem paths.
- Carry material identities through the existing `MapInfo` seam, with cardinality
  and known-ID checks before presentation. Reserve geometry version changes for
  changed collision meaning. Separate the accepted collision contract from any
  new presentation capability needed for correct client behavior.

Use institutional bone/green concrete and warm service accents for this Earth
annex, following the [art bible](../ART_STORY_BIBLE.md). The enclosed fixture's
uniform repeated panels are a diagnostic baseline, not the environment kit.

## Verification

1. Decode valid and malformed documents, unknown fields/versions, truncated and
   oversized files, duplicate IDs, unsupported surfaces and construction limits.
   Test actual startup refusal before readiness and useful errors without dumping
   file contents. Commit a small valid fixture and representative failure cases.
2. Run ordinary human/agent actions from explicit indoor spawns through both M01
   routes. Prove the balcony, underpass, stair entry/exit, lift approach and shots
   across levels. No teleport or test-only geometry substitution in this proof.
3. Exercise the live version gate, MCP observation, local decision brain,
   standalone scripted agent and eyes spectator with the loaded map. Validate
   disconnects and map replacement, including a reused content identity.
4. Inspect the whole blockout in OpenGL and Vulkan, including camera clearance,
   readable destinations, material changes and the absence of open-sky gaps.
   Measure traversal length and dead time; a connected graph alone is insufficient.
5. Preserve the existing six-map mixed roster and complete seeded CPU recordings.
   Run workspace, coverage and Godot gates. Update the mission's implementation
   checklist with evidence and missing gameplay, not a premature complete label.

## Research constraint

Checked 2026-09-19: Serde's [container attributes](https://serde.rs/container-attrs.html)
and [flattening reference](https://serde.rs/attr-flatten.html) explicitly disallow
combining `flatten` with `deny_unknown_fields`. Use named nested fields for strict
authoring records and a deliberate boundary into canonical solids. Keep wire
compatibility separate from stricter authoring input; test both rather than
changing a shared deserializer's acceptance accidentally.

## Implementation and current evidence

`server/maps/m01-recall-notice.json` defines 58 finite volumes, four indoor entry
spawns and eleven route landmarks. One `RuntimeMap` handle supplies both built-in
and authored geometry to simulation, spawns, controllers and `MapInfo`. Arcade
cache and ring order are preserved. The strict 1 MiB authoring boundary rejects
unknown fields, unsafe placements and unreachable destinations before binding.

`--map-file` is opt-in traversal authoring with `--bots 0`. It rejects arcade
rotation, Episode 0 and rule overrides. There is no timer, boss or arena pickup
layout in this mode. Snapshot text identifies the blockout. Existing weapon
selection remains available for geometry inspection; campaign inventory is not
implemented. No menu entry claims that M01 is finished.

Registered concrete, enamel, service steel, records tile and lift panels travel
through the optional `MapInfo.presentation` field. Legacy maps omit it. Clients
validate identifiers and exact correspondence with collision solids before
replacing the world. The authoring schema and run commands live in
[`server/maps/README.md`](../../server/maps/README.md).

Local server tests walk human and agent roles through the main and alternate
stairs, underpass, office and lift using ordinary session actions. Live socket
tests exercise human/agent/spectator geometry and movement plus legacy rejection.
An MCP test observes the loaded map and moves through its entry. An eight-second
smoke runs the standalone scripted client and local decision brain against each
other in this map; both score frags, and the brain records zero paid calls.

Both ten-state live tours pass and were inspected on Windows/AMD through OpenGL
compatibility and Vulkan Forward+. Inspection found a gap above the maintenance
wall; the solid was raised and both tours repeated. Current evidence lives in
`.agents/qa/m01-{opengl,vulkan}-final`. The views establish enclosed spaces and
kit variation, while exposing missing props, signage, room lighting and encounters.

The OpenGL manifest's authoritative movement samples measure 119.1 metres and
24.64 seconds through the first lift visit, including the underpass inspection
detour. The full two-route tour measures 262.3 metres and 53.76 seconds inside
movement probes. These exclude capture waits and contain no combat, interaction
or exploration decisions. They are not first-play times. The proposed 10-15
minute mission remains unproven; build encounters and discovery before deciding
whether the route needs more rooms, and avoid padding it with walking.

Workspace verification passes 629 Rust tests with 95.68 percent unfiltered line
coverage, warnings-denied Clippy, release build and dependency checks. All 18
Godot harnesses pass. Surface validation tests caught a typed-array lookup on an
unvalidated Variant; the boundary now checks the type before membership. The
checker rejected the engine error even though that harness printed PASS.

CPU runs, release build on Windows, seed 42, 12,000 ticks each:

| Bots / map | p99 tick ms | Maximum tick ms | Complete trace matches v0.22.0 |
|---|---:|---:|---|
| 16 / Arena Duel | 0.655 | 2.194 | yes |
| 64 / Reclamation Gulch | 1.901 | 4.380 | yes |
| 128 / Tripoint Works | 6.029 | 10.706 | yes |

Reports: `.agents/bench/authored-{16,64,128}.json`. These pass the existing CPU
budget and repeat-trace gates. They do not measure network scale, rendering or
GPU bot compute, and do not establish a speed improvement.

One workspace test reused a sprite-tool binary compiled from an earlier removed
worktree. Its embedded manifest path pointed outside the current tree. Cleaning
that package and rebuilding restored the palette test without changing code or
assertions. Keep target directories isolated across worktrees.

The full 21-state arcade/menu/effects tour also passes. Its contact sheet and
both effect strips were inspected, and the release gallery was refreshed from
`.agents/qa/authored-full`. This remains separate from the M01 captures.

The six-map mixed-client roster passes its unchanged assertions with
2/6/6/8/12/16 clients. Reports are in `.agents/playtest/authored/`; CI repeats this
gate before integration. The largest run recorded 79 frags and eight early
spawn deaths, which passes the current statistical gate but is not proof that
spawn balance is finished. GitHub checks on #177 own cross-platform integration
evidence. Continue with [M01 discovery](weapon-economy.md#next-bounded-increment-m01-discovery),
encounters, interaction, objectives and checkpoints. A connected blockout still
does not establish a fun ten-minute mission.
