# Authored campaign map data

**Status:** in local verification, 2026-09-19. Follows [finite-volume geometry](campaign-spaces.md), shipped in #176.
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
The first ten-state OpenGL tour passes through actual input and networking.
Initial full-size room captures were inspected; revised view headings and Vulkan
inspection are in progress. The first views establish enclosed spaces and kit
variation, while exposing the missing props, signage, room lighting and encounters.

One workspace test reused a sprite-tool binary compiled from an earlier removed
worktree. Its embedded manifest path pointed outside the current tree. Cleaning
that package and rebuilding restored the palette test without changing code or
assertions. Keep target directories isolated across worktrees.

Remaining before integration: final full workspace/coverage and client checks,
seeded CPU trace comparison, six-map mixed roster, both inspected M01 rendering
paths, current full tour, consumer smoke and CI. Then continue with inventory,
encounters, interaction, objectives and checkpoints. A connected blockout still
does not establish a fun ten-minute mission.
