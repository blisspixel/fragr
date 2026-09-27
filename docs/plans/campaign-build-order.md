# Campaign build order

**Status:** planned, revised 2026-09-26. No full campaign mission is accepted. The current sequence is the [full build order](../ROADMAP.md#full-build-order-2026-09-22): complete M02 on the durable run, then one accepted level at a time. M01 still has a fresh-player gate near 1.0.
**Goal:** deliver twenty levels in five episodes and a conditional epilogue in [CAMPAIGN.md](../CAMPAIGN.md) through
bounded, verifiable milestones. [Mission briefs](../CAMPAIGN-MISSIONS.md) define
content; this plan defines dependencies.
**Spend:** local design/code work is free. Paid asset batches use current quota,
an explicit approved cap, and the existing developer pipelines.

## Actual baseline

| Concern | Present behavior | Campaign gap |
|---|---|---|
| Maps | Six arena layouts, an M01 development mission and an M02 combat graybox; shared finite geometry, keyed signs and bounded details | Complete mission layouts, room kits and transitions |
| Combat | M01 fists, found Pistol and Rifle, private finite inventory, one ammunition count per type and supplies; arcade full arsenal | Remaining arsenal, projectiles, authored encounter balance and finished sound sets |
| Movement | Shared gravity, jump, steps, ceilings and overlapping floors with a verified GDScript mirror | New traversal features require explicit geometry support and live tests |
| Enemies | Rule bots, elite/boss prototype, authored human Clerk and Sweeper bot with phased attacks and directional animation | Full enemy roster, final art, encounters and balance |
| Episode | Calibration prototype; M01 transfer/gate/departure shipped in v0.26.0 | Full story missions, rescue outcomes and campaign transitions |
| Runs and persistence | Versioned local M01 run file, three mission-start continues, entry restoration and local service-record history | Cross-mission carry, episode refill, achievements, rescue outcomes and epilogue unlock |
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
   within a four-hour successful campaign run. Inspect the whole route. No paid
   scene needed to prove it. Human/agent control and eye-view spectators must work.
4. **Build M02 and the early rescue.** Add companion state, release objectives,
   Shotgun and Crawler encounters, rescue-aware mission retry, reunion and
   optional text/voice. The Jammer first appears in level 3.
   Prove joins and retries cannot duplicate or erase people.
5. **Finish Episode I, levels 3 to 5.** The rail yard introduces the Jammer,
   the home district introduces the Notary as a direct threat, and the departure
   level introduces the grenade against a Heavy Sweeper. Persist optional rescue
   outcomes and test M01 through level 5 with several survivor states.
6. **Build Episodes II and III one level at a time.** Follow the accepted
   [mission treatment](../CAMPAIGN-MISSIONS.md) across custody, the Moon, ship
   and coalition work. Add only the enemy, traversal or weapon capability the
   next level teaches, and test its distinct role and carry state.
7. **Build Episode IV.** Make the Union defeat earned through the inhabited and
   industrial fronts. Show other communities' contributions without a single
   victory switch or a premature wipe.
8. **Build Episode V and the conditional epilogue.** Prototype the three-level
   wipe survival route before locking each encounter budget. Free-agent friends
   secure a local reprieve. Surviving the finale unlocks the short playable
   aftermath; exhaustion receives its own ending and credits. Both outcomes
   establish consequences without declaring the catastrophe justified.
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

Vehicles are deferred from M01, but planned for level 14's combined-arms launch works.
Prove a small server-owned drivable-vehicle slice before building that encounter;
the [level 14 brief](../campaign/l14-launch-authority.md) owns its scope.
Alien combat, dimensional traversal, the later Inheritance command mode, and
large-scale hosting remain beyond separately measured milestones.
