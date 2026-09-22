# Campaign build order

**Status:** planned, revised 2026-09-21. No full campaign mission is accepted. The sequence is the [full build order](../ROADMAP.md#full-build-order-2026-09-22): two readable enemies, then secrets and a fresh-player gate, then persist the run, then one mission at a time.
**Goal:** deliver ten missions and a conditional epilogue in [CAMPAIGN.md](../CAMPAIGN.md) through
bounded, verifiable milestones. [Mission briefs](../CAMPAIGN-MISSIONS.md) define
content; this plan defines dependencies.
**Spend:** local design/code work is free. Paid asset batches use current quota,
an explicit approved cap, and the existing developer pipelines.

## Actual baseline

| Concern | Present behavior | Campaign gap |
|---|---|---|
| Maps | Six arena layouts and a validated M01 document; shared finite geometry, keyed signs and bounded details | Complete mission layouts, room kits and transitions |
| Combat | M01 fists, found Tack/Flechette, private finite inventory, reload and supplies; arcade full arsenal | Remaining arsenal, projectiles, authored encounter balance and finished sound sets |
| Movement | Shared gravity, jump, steps, ceilings and overlapping floors with a verified GDScript mirror | New traversal features require explicit geometry support and live tests |
| Enemies | Rule bots, elite/boss prototype, authored human Clerk and Sweeper bot with phased attacks and directional animation | Full enemy roster, final art, encounters and balance |
| Episode | Calibration prototype; M01 transfer/gate/departure shipped in v0.26.0 | Full story missions, rescue outcomes and campaign transitions |
| Runs and persistence | Settings; in-memory solo M01 run with three continues and entry restoration; local service-record history | Campaign disk saves, cross-mission carry, achievements, rescue outcomes and epilogue unlock |
| Co-op | Allied campaign participants, encounter wipe reset; shared mission boarding and four-seat admission shipped with live party evidence | Optional scope undecided; no mandatory duo, revival or all-mission co-op requirement |
| Presentation | Retro front end, HUD, radio and viewmodels; localized M01 text opening and party readiness shipped in v0.28.0 | Finished scene art/narration, companion scenes, complete character/weapon/effect motion |

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
   physical interaction, extraction, and mission-start continues through existing
   server seams. Separate PRs can build these bounded systems with small fixtures;
   fixtures are not shipped campaign levels. The first geometry increment is
   [enclosed and layered spaces](campaign-spaces.md), required by M01's balcony.
   [Authored campaign maps](authored-campaign-maps.md) then brings M01's route
   through the normal server with validated data and explicit indoor spawns.
3. **Complete M01 as the quality target.** Full room sequence, flanks, secrets,
   discovery economy, animation, impact and room audio, localized opening,
   extraction, limited continues, and results. Target an 8-10-minute mission
   within a 2-3-hour successful campaign run. Inspect the whole route. No paid
   scene needed to prove it. Human/agent control and eye-view spectators must work.
4. **Build M02 and the early rescue.** Add companion state, release objectives,
   Jammer behavior, rescue-aware mission retry, reunion and optional text/voice.
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
8. **Build the wipe finale and conditional epilogue.** Sudden onset, scale-revealing
   scene, varied survival route and a local reprieve obtained by free-agent friends.
   Prototype the roughly 33-minute survival target before committing the encounter
   budget. Remaining continues allow retries; exhaustion ends with credits.
   Survival alone unlocks short playable aftermath and years-later healing. Both
   endings establish world consequences and briefly tease the wider universe.
9. **Validate and refine the complete run.** Every mission and survivor path,
   continues, run exhaustion, solo/agent play, spectator transitions, localization,
   accessibility, exports, performance, and fresh-player comprehension and fun.
   Revise pacing and assets where evidence fails. Finish the brief sequel tease.

A milestone can span several small PRs. Never call it complete because a
framework exists. Each mission needs its own implementation checklist and
playtest receipt when work begins, linked here rather than empty tickets.

## Architecture and protocol

Use [campaign-continuance.md](campaign-continuance.md) for framework requirements.
The Rust server owns objectives, entities, inventory, transitions and saves;
Godot renders them. Shared typed protocol carries identifiers, not localized
English sentences masquerading as state. MCP receives the same relevant state
without entering the combat loop. No provider is required at player runtime.

## Evidence per mission

- Deterministic success/failure and malformed-data tests at owning boundaries.
- Solo completion with human and agent control; spectator follow; mission retries,
  exhausted runs, saves and relevant rescue states. Co-op evidence is required
  only for missions or modes explicitly selected for that capability.
- Rendered motion through every principal route, stairs, doors, pickup and fight.
  Inspect OpenGL/Vulkan paths and record actual hardware, not inferred support.
- Text-only, muted radio, missing optional voice, skipped scenes, long translated
  text, readable fonts, and changes of language.
- Measurements appropriate to the encounter and render budget. Fresh-player
  observations on route clarity, enemy reads, dead time and repeat-play interest.
- Asset manifests, roadmap status and release evidence updated together.

Vehicles are deferred from M01, but planned for M08's combined-arms launch works.
Prove a small server-owned drivable-vehicle slice before building that encounter;
the [M08 brief](../campaign/m08-weight-of-permission.md) owns its scope.
Alien combat, dimensional traversal, the later Inheritance command mode, and
large-scale hosting remain beyond separately measured milestones.
