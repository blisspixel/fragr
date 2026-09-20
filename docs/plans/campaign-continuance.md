# Campaign framework requirements

**Status:** proposed architecture, revised 2026-09-19. No external map manifest,
campaign save format, or full enemy-entity system is implemented. This replaces
the earlier decision-complete claim and conflicting map/episode prescriptions.

**Goal:** support [the campaign](../CAMPAIGN.md) through the Rust authority and
Godot presenter without parallel simulation or duplicated geometry.
**Sequence:** [campaign-build-order.md](campaign-build-order.md).
**Spend:** no paid infrastructure or new dependency selected by this document.

## Maps as data

Start with a versioned, validated, server-owned JSON representation, consistent
with the user's authoring preference. Authoring can use text and route diagrams;
an editor/exporter is optional. Source map data must drive collision, navigation,
encounters, rendering geometry, and interactions, with a shared content identity.

Current solids support heightfields, not arbitrary stacked rooms. Ship, archive,
and office designs require ceilings, overlapping accessible floors, doors, and
occlusion that the current representation cannot simply pretend to provide.
Design those explicit 3D volumes and tests before authoring unsupported geometry.

The minimal map contract needs stable IDs, bounds, materials, geometry, safe
spawns, encounters, items, interactions, objective links, secrets, and exits.
Campaign metadata links mission IDs, checkpoints, rescue state, and text keys.
Separate static content from mutable session state; do not serialize a live game
by overwriting its map source.

Validate finite coordinates and ranges, unique IDs, referential integrity,
spawn clearance, legal triggers, mandatory exits, content size limits, and
supported versions before readiness. Reject unknown critical variants. Bound
navigation preprocessing and entity budgets. Reachability checks prove geometry
under stated states; playtests still establish whether the route is understandable.

TrenchBroom and func_godot were earlier proposals, not installed commitments.
Do not add two loaders or a client-owned collision interpretation. If an editor
materially helps, verify current compatibility, maintenance and format semantics
in a bounded spike. Prefer an existing mature parser over inventing one for a
standards-heavy format. No dependency or exact CLI is selected here.

## Enemies and encounters

[ENEMIES.md](../ENEMIES.md) owns behavior design. Define typed server-owned enemy
states with explicit sensing, attack tells, damage, pain, disable/death, and
limited reactivation where applicable. Presentation cannot decide hits or wakeups.
An enemy's legal status and faction are distinct from its body and gameplay role.

Represent imposed Union control separately from consciousness or chassis. At the
wipe every still-controlled bot changes to the Inheritance's collective while
free agents remain independent. Transition once on the authority, synchronize
late joiners, and test freed/captive/controlled states through checkpoint reload.
Neither runtime labels nor save diagnostics may settle the unknown fate of minds
after correction or absorption. A restored checkpoint restores gameplay state;
it is not an in-world cure for correction.

Use shared movement, combat and navigation where appropriate. Do not make every
monster a network player solely to reuse a scoreboard. Preserve current boss
behavior until its replacement has tests and a deliberate migration.

Encounter data chooses roster, placement, difficulty, and physical triggers.
Projectiles, line of sight, doors, friendly teams and revival need real
simulation paths and deterministic tests. A table containing a monster name is
not an implemented monster.

## Campaign state and saves

A server-owned party run records content version/hash, mission and checkpoint,
difficulty, player identities/body selections, inventory, shared keys, objective
states, companion state, and survivor outcomes. Save schemas are versioned.
Write atomically; validate before loading; preserve the prior valid save after
failure. Define content mismatch and migration behavior before releases.

Separate checkpoint rollback from permanent narrative outcomes. Mission replay
cannot silently overwrite the main run. A disconnected carrier cannot delete
a required object. Drop-ins and revived players receive safe inventory and
placement rules; they cannot duplicate pickups or farm rescue rewards.

## Story presentation

Typed events reference stable story IDs, line IDs, parameters and authoritative
state. Godot resolves localization and optional voice/scene resources through
existing settings and audio routing. Keep presentation acknowledgements separate
from mission success. Late participants receive current state and a recap.

Basic text, captions, skips and checkpoint-safe scene replay belong in the first
mission. Use the existing localization plan and native Godot translation tools;
do not build a second bespoke translation system for cutscenes.

## Verification

Malformed map/save fixtures, trigger ordering, completion/retry, simultaneous
interactions, every rescue branch, join/leave, spectator state, and text-only
playback need evidence. Prove collision and rendering agree on stacked spaces.
Run the normal repository checks before integration. Keep factual state in the
roadmap; future maps and scene assets remain planned until loaded and played.
