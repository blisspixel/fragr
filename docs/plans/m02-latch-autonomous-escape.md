# M02 Latch autonomous escape

**Status:** planned, 2026-09-27. Build after the M02 Latch release and
[M01 to M02 run carry](m01-m02-run-carry.md) drafts are integrated. This plan
does not claim that Persons Unknown is finished.

## Goal and reason

Make Latch a visible, server-owned ally for the second half of Persons Unknown.
The current ward release has an authoritative guard victory and local control,
but Latch remains a fixed presentation in the ward while the player fights to
the dock. The [accepted M02 brief](../campaign/m02-persons-unknown.md) calls
for Latch to free another captive, then help through the processing floor.
The [campaign contract](../CAMPAIGN.md#solo-co-op-agents-and-watching) makes
allies autonomous and keeps the solo route independent of their pathfinding.

Success is a played sequence: release Latch, see them help the captive, fight
with them through the floor, and leave by the dock. A late watcher sees the
same ally and ward result. The scene, actor and mission facts must agree.

## Lore and product boundaries

- Latch is a conscious free embodied agent, not a Union bot, a second player
  seat, a companion-control interface or a revive target. Their first free
  action is opening the other restraint. They recognize either chosen player
  body, then read Low Water on the transfer list. Keep the reunion body-neutral.
- Latch has a practical, capable presence and may disagree later. Do not fix
  their face, age, voice, romantic relationship or final chassis in this
  gameplay slice. Use the [cast anchors](../lore/cast.md#visual-continuity): a
  provisional midweight repaired chassis, unequal forearm plates, worn bone
  and dark steel, with a small muted cyan patch. It must read apart from
  issued black and red Union bodies, without using color alone for allegiance.
- Ordinary combat cannot kill Latch or fail a rescue. A blocked path, absent
  ally or lagging ally cannot stop a solo participant from completing the dock
  objective. Do not let Latch block a narrow doorway or required control.
- Keep the Jammer and the warning to Mara in level 3. Low Water is the home
  district in level 4. The Notary remains an unreachable gallery tableau in
  M02 and its first fight belongs to level 4. Captive suffering is not a joke.

## Scope

1. Give the released companion one authoritative identity and lifecycle.
   Spawn exactly once from the completed `companion_released` objective, after
   its guard and Use requirements. Bind the actor to the mission attempt,
   remove it on retry or party reset, and restore its visible state for late
   join and reconnect. No client timer may create or delete the real ally.
2. Join the fixed ward scene to the moving actor. Latch opens the second bay
   before their combat movement begins. Choose a server-owned handoff tied to
   the release tick and a bounded presentation phase; the client must not
   render two Latches or show a teleport from the frame to the floor. A
   skipped scene and a late observer reconstruct the completed ward and the
   current actor without replaying the one-time release.
3. Follow secured, reachable route points from ward to processing floor to
   dock, using the existing navigation map and staggered search budget.
   Latch can recover from a blocked route and keep passage clear. They do not
   trigger encounters, collect supplies, operate required controls, take a
   party seat or count as aboard. The player may advance or depart without
   waiting for them. No teleport is presented in the player's sightline as
   a routine recovery mechanism.
4. Give Latch bounded supporting fire only when a server-verified Union target
   is visible. The same server combat path resolves their shots and hits.
   Never accept external actions for their identity. Player and agent
   participants are never targets, even when arena friendly fire is enabled.
   Keep ally fire legible and useful without letting it clear the entire
   mission while the player waits. If combat creates a kill or damage record,
   its source must be truthful and must not award a player's achievement or
   pickup credit.
5. Present a distinct moving, turning and firing ally silhouette with a
   readable weapon and consistent feet registration. Use a local provisional
   asset or authored Godot geometry. Inspect motion in the actual ward,
   processing floor and dock lighting, at first person and spectator angles.
   Add localized short combat barks only if they help orientation with sound
   muted; no paid voice or image is required.

## Architecture and protocol

`server/src/protocol/actors.rs` owns campaign allegiance. Add an explicit
companion identity to `CampaignActor`, with only the fields the client needs
to render it. Do not infer faction from callsign, control role, body kind or
the existing `!is_campaign_enemy()` shortcut. Audit the source paths that
currently treat every non-Union pawn as a participant: admission and slot
counts, roster and scoreboard, mission readiness and departure, spectator
follow lists, aim assist, pickups, statistics, encounters and reset. Update
`client/scripts/actor_state.gd` and `player_pawn.gd` to validate and render
the new kind strictly. Preserve the M01 and arena wire shapes.

`server/src/mission/m02.rs` owns the release fact and attempt. The companion
controller belongs with the encounter and mission simulation, using the
existing `GameState` pawn, action, shot and collision seams rather than a
separate client simulation. `server/src/session.rs` runs its intent inside
the established 20 Hz tick, and `navigation/controller.rs` supplies bounded
routes. Reuse the existing four-search-per-tick scheduling; measure any tick
cost under the M02 roster. Keep the MCP adapter on its slow control plane;
there is no new campaign tool and no privileged client command for Latch.

Choose the next gameplay capability after 18 during implementation and make
M02 readiness require it for human, agent and spectator readers. Add the
identity, any new actor phase and optional event to `docs/protocol.md` and
validate it in Rust, Godot and adapter readers in the same change. If a field
is needed for the ward-to-actor handoff, derive it from the server's mission
attempt and release timing; avoid duplicate mutable release flags. Keep the
M01 movement mirror and golden vectors in step if shared movement changes.
Changing established difficulty timing requires a new
`CAMPAIGN_RULES_REVISION` and matching client validation.

## Non-goals

No tactical orders, required co-op, revival, ordinary-combat death for Latch,
escort timer, new mission objective, extra physical gate or complete M02 art
pass. Optional captive groups, the Notary fight, Mara contact, level 3 launch,
new weapons, cloud hosting and UDP remain separate work. The ally does not
make the M02 fresh-player gate pass by itself.

## Verification and acceptance

- Deterministic server tests prove early or forged Use cannot spawn Latch;
  lawful release spawns one; duplicate Use, tick, reconnect and late join do
  not duplicate them. Wipe before and after release restores the restrained
  ward and removes the old actor. A new attempt gets one new actor. M01 and
  arena tests continue to pass.
- Trace a live human and an agent controlled participant from release through
  the processing floor and dock. Test ordinary and bypass ward arrival, a
  player who sprints ahead, a blocked corridor, a missing or stalled ally,
  and solo departure. No softlock, doorway obstruction or fabricated rescue
  outcome is acceptable.
- Test attack and damage boundaries: Latch can fire at a visible Union actor;
  walls block shots; Union targets may target the ally without causing a
  story death; allies and participants cannot harm one another; no pickup,
  player kill, record, slot or score is credited to Latch. Record damage and
  encounter pacing on at least Standard and Severe rather than assuming the
  extra gun preserves difficulty.
- Godot strict validation rejects malformed or contradictory ally state.
  Headless harnesses cover one visible Latch, ward handoff, retry, scene skip,
  muted audio and late observation. Regenerate the standard tour, inspect
  actual first-person motion and at least one continuous ward-to-dock play
  sequence. A still frame alone does not prove the ally can move or help.
- Run format, Clippy, workspace tests, unfiltered 90 percent coverage,
  release build, dependency policy, deterministic benchmark, live playtests,
  mixed roster, 120-second soak, pinned Godot checks and CI before calling
  the engineering slice implemented. Record measured tick and memory results
  with platform and roster; do not infer public-host or larger-map capacity.
- An unsteered player must understand the Crawler lesson, Latch's rescue and
  Low Water with voice and radio muted, and recognize Latch helping during
  escape. Record their words, deaths and stalls. This human gate stays open
  until it actually passes; automated routes are authoring evidence.

## Spend and handoff

External API and cloud spend for this sprint is **$0**. Use authored local
assets and committed audio fallback. The separate $20 current-build allowance
and $50 repository cap are not permission to call a paid provider. No cloud
apply, paid generation, merge, tag or release is part of this plan. Record
implementation evidence here and update the single Full build order section
of the roadmap when the next rung changes. Keep the root README concise and
place controls, save behavior and mission detail in its linked guides.
