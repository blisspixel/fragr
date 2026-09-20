# Campaign build order

**Status:** planned, revised 2026-09-19. No full campaign mission is implemented.
**Goal:** deliver the twelve-mission story in [CAMPAIGN.md](../CAMPAIGN.md) through
bounded, verifiable milestones. [Mission briefs](../CAMPAIGN-MISSIONS.md) define
content; this plan defines dependencies.
**Spend:** local design/code work is free. Paid asset batches use current quota,
an explicit approved cap, and the existing developer pipelines.

## Actual baseline

| Concern | Present behavior | Campaign gap |
|---|---|---|
| Maps | Six arena layouts and a validated M01 document; shared finite geometry and surface presentation | Authored encounters, mission links and complete room dressing |
| Combat | M01 fists, found Tack/Flechette, private finite inventory, reload and supplies; arcade full arsenal | Remaining arsenal, projectiles, authored encounter balance and finished sound sets |
| Movement | Shared gravity, jump, steps, ceilings and overlapping floors with a verified GDScript mirror | New traversal features require explicit geometry support and live tests |
| Enemies | Rule-bot behaviors using Player; elite/boss prototype | Separate authored enemy states, human/captive/elite distinctions, encounter placement and animation |
| Episode | Calibration phases: NODS, jammer, Auditor, win/fail | Story missions, release/extraction objectives, campaign transitions |
| Persistence | Player settings | Versioned party campaign save, checkpoints, inventory and rescue outcomes |
| Co-op | Multiple fighters can connect | Teams, revive/wipe, mission joins, shared objective state, save ownership and reconnect |
| Presentation | Retro front end, current HUD, radio and idle viewmodels | Localized framing, companion scenes, complete character/weapon/effect motion |

Navigation PR #172 shipped in v0.21.0 after local verification and green CI,
including fixes for the first run's map-3 stall and map-5 spawn-death failures.
These are existing arena traversal improvements, not a completed campaign map.

## Milestones

1. **Freeze the first mission treatment and core character references.** Review
   the story's causal route and open decisions. Draw M01's route graph, sightlines,
   encounter beats, and asset list before coordinates. Establish a complete
   character/weapon style sample rather than generating disconnected stills.
2. **Build the first campaign-sized gameplay foundation.** Add validated map
   data, required geometry support, melee/sidearm/ammo, two readable enemy types,
   physical interaction, extraction, and a minimal checkpoint through existing
   server seams. Separate PRs can build these bounded systems with small fixtures;
   fixtures are not shipped campaign levels. The first geometry increment is
   [enclosed and layered spaces](campaign-spaces.md), required by M01's balcony.
   [Authored campaign maps](authored-campaign-maps.md) then brings M01's route
   through the normal server with validated data and explicit indoor spawns.
3. **Complete M01 as the quality target.** Full room sequence, flanks, secrets,
   discovery economy, animation, impact and room audio, localized opening,
   extraction, retry, and results. Inspect the whole route. No paid scene needed
   to prove it. One to four humans/agents and eye-view spectators must work.
4. **Build M02 and the early rescue.** Add companion state, release objectives,
   Jammer behavior, rescue-aware checkpoint data, reunion and optional text/voice.
   Prove joins and retries cannot duplicate or erase people.
5. **Build M03 and finish Act I.** Home district, mixed fights, evacuation,
   persistent optional rescues, and the lunar transition. Run M01-M03 end to end
   with several survivor states. This is the first substantial campaign release.
6. **Build Act II, one mission at a time.** Lunar kit and Rail encounters, custody
   archive and Auditor, then shipboard circulation and boarding. Implement only
   the next needed enemy/projectile/weapon capability and test its distinct role.
7. **Build Act III.** Martian inhabited/industrial environments, coalition
   consequences, Walker and mixed squads, then earned Union defeat on Earth.
   Show other communities' contribution without an omnipotent victory switch.
8. **Build Act IV and the playable coda.** Sudden onset, scale-revealing scene,
   immediate aftermath, return to a changed home, final rescues and years-later
   healing. Reuse locations through authored structural change, not cosmetic tint.
9. **Validate and refine the complete run.** Every mission and survivor path,
   checkpoint recovery, solo/co-op/agent play, spectator transitions, localization,
   accessibility, exports, performance, and fresh-player comprehension and fun.
   Revise pacing and assets where evidence fails. Finish the brief sequel tease.

A milestone can span several small PRs. Never call it complete because a
framework exists. Each mission needs its own implementation checklist and
playtest receipt when work begins, linked here rather than twelve empty tickets.

## Architecture and protocol

Use [campaign-continuance.md](campaign-continuance.md) for framework requirements.
The Rust server owns objectives, entities, inventory, transitions and saves;
Godot renders them. Shared typed protocol carries identifiers, not localized
English sentences masquerading as state. MCP receives the same relevant state
without entering the combat loop. No provider is required at player runtime.

## Evidence per mission

- Deterministic success/failure and malformed-data tests at owning boundaries.
- One-player and four-player completion; mixed humans/agents; drop-in/out;
  spectator follow; wipe/retry/save; relevant rescue-state combinations.
- Rendered motion through every principal route, stairs, doors, pickup and fight.
  Inspect OpenGL/Vulkan paths and record actual hardware, not inferred support.
- Text-only, muted radio, missing optional voice, skipped scenes, long translated
  text, readable fonts, and changes of language.
- Measurements appropriate to the encounter and render budget. Fresh-player
  observations on route clarity, enemy reads, dead time and repeat-play interest.
- Asset manifests, roadmap status and release evidence updated together.

Deferred: vehicles, alien combat, dimensional traversal, the later Inheritance
command mode, and large-scale hosting beyond separately measured milestones.
