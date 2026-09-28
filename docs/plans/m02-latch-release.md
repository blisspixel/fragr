# M02 Latch release

**Status:** in flight in [draft PR #272](https://github.com/blisspixel/fragr/pull/272),
2026-09-27. Stacked after the Crawler descent in
[draft PR #270](https://github.com/blisspixel/fragr/pull/270).

## Goal and reason

Make the first M02 rescue a server-owned event with a visible cause. Reaching
the ward must not release Latch by proximity. The player reaches the frame,
defeats the ward guards, operates the local restraint control, and sees Latch
free themself and attend to another captive before the party can depart.
That order is the accepted Level 2 story in
[`docs/campaign/m02-persons-unknown.md`](../campaign/m02-persons-unknown.md).
The current graybox instead completes `companion_released` when a participant
arrives near an empty frame. It gives no guard prerequisite, no release action,
no Latch presentation, and no persistent visual result for a late observer.

## Canon and boundaries

Latch is a conscious embodied agent threatened by forced correction. They
recognize the protagonist whether the chosen player body is human or synthetic.
The facility's act stops on ward victory. Latch's first free action is to open
another captive's restraint; the transfer list reveals Low Water and gives
them a reason to help others. They are not an escort failure condition, a
second player seat, a damage target, or a revive system. The precise
relationship label, face, age, voice casting and final chassis design remain
open. Avoid writing dialogue that settles them by accident. The Notary is a
tableau here and first fought in level 4; the Mara warning waits for level 3.

This slice delivers the authoritative release and a provisional local ward
presentation. It does not claim that Latch already follows or fights on the
processing floor. A moving autonomous ally needs its own snapshot identity,
client validation, hostility audit and a later gameplay capability in its own
bounded rung.
M01-to-M02 run carry and durable M02 continues remain separate work. Wipes in
the development child reset the ward and release state together.

## Server architecture

1. Author a linear `ward_reached` arrival, `companion_released` use at the
   restraint frame's west face, then `party_departed` arrival. The sole
   required use stays within M02's existing one-control budget. Keep a
   standing approach near [7, 0, -11], preserve nav and eye-to-panel LOS, and
   relocate the existing west-face lockers so the panel can be read. The use
   action must be local to the frame; no remote rescue command.
2. Add an optional validated encounter prerequisite to an M02 objective and
   name `ward_guards` on `companion_released`. Resolve authored encounter IDs
   during map preparation, before readiness. The map loader currently
   prepares objectives before it validates encounters, so validation must
   deliberately cross that order or use the document's strict IDs. An unknown
   ID fails map load. Reuse the existing `Use`, prompt and agent controller
   wire. The server suppresses the prompt and rejects early or forged use
   until the group reaches Complete after its last guard falls. Duplicate use
   cannot repeat the release or advance beyond the next step.
3. Make ward activation independent of `crawler_pack` completion and add a
   frame-side trigger. A player who bypasses the pack must not reach an inert
   ward and softlock the solo route. The ordinary path still meets the pack
   first. Preserve the few-doors rule and reachable ward and dock routes.
4. Derive the released fact from the existing server `M02Progress.index` and
   project it in `MissionState.m02.completed` to human, agent and spectator
   readers. A late join, reconnect or skipped local scene must reconstruct the
   same restrained or released state. Do not add a second mutable client
   release flag that can disagree with the server. A wipe resets encounter
   groups and M02 progress together. A released Latch does not need a
   collision body to let a solo participant leave through the dock.
5. The machine stops on ward victory, before the later release use. Add
   `M02ObjectiveState.ward_secured`, derived for each projection from the
   authoritative `ward_guards` Complete group, never stored in a second
   mutable flag. The frame's released state derives from
   `companion_released` in `completed`. A late observer can reconstruct both
   facts. Do not have the client infer victory from missing enemies, which
   can be dead, culled or unseen.

The release action reuses `MissionObjectiveAction::Use`. The new durable
`ward_secured` projection needs gameplay capability 17 because the Godot
M02 validator checks the exact object shape. M01 and arena requirements remain
unchanged. This does not change difficulty semantics or
`CAMPAIGN_RULES_REVISION`. Update `docs/protocol.md`, Rust and Godot readers,
the adapter, local readiness and tests together. A future moving ally needs
a later capability and separate actor contract. No second campaign door
enters MCP.

## Presentation

Use an original provisional Latch figure at the restraint frame, visually
separate from Union issue black and red. A restrained pose becomes a released
pose when the server fact changes. Show the machine falling quiet on ward
victory. Latch then visibly opens a second occupied restraint before speaking,
and reads Low Water on the transfer list in a keyed, legible beat. The second
bay stays open and the transfer-list result has a short recap for a late
observer or skipped scene. Keep the reunion body-neutral, localized and
understandable with Voice muted or a missing optional asset. The scene may
be skipped or joined late without changing the objective.
The player remains in the ward; the existing full-screen between-level
`ScenePlayer` is a reference for keyed text and input dismissal, not a reason
to move rescue authority into presentation. Use the existing `Voice` bus if
an approved voice asset is added later. No external asset generation is needed
for this slice.

The screen should answer three questions: who was on the frame, why the
correction stopped, and why Low Water matters. A short nonblocking recap or
visible released state must make that result legible to reconnecting players
and spectators. No joke at the captives' expense and no fixed romance wording.
Update `mission_hud.gd` and the keyed catalog for `ward_reached`, the local
restraint use prompt and dock departure. Strict client validation and the
agent adapter must accept the new objective order and the typed ward fact.

## Verification and acceptance

- Map-load rejects unknown prerequisites, invalid panel geometry and a route
  that cannot reach the control. Tests prove both ordinary and bypass ward
  activation, with no inert guards at the frame.
- A seeded live server route proves early arrival and forged use fail, last
  guard death gates the next tick, lawful use advances once, duplicate use is
  inert, and shared dock departure works with one player. Prove range,
  facing, LOS, early briefing and death refusal. Test both human and agent
  controller entry points.
- Wipe before and after release resets the ward, machine and objective. A
  reconnect and late spectator see the same completed state. Existing M01
  and arena contracts remain unchanged. The agent adapter validates the same
  objective and new event or field if one is added.
- Pinned Godot headless checks cover all keyed text, missing optional audio,
  muted Voice, skip, retry, late state, HUD objective/prompt copy and no
  duplicate presentation. Inspect a live rendered ward approach, restraint,
  guard win before use, release, actual second-bay opening, Low Water list
  reveal and dock route. Publish the visual tour for any player-facing change.
- Record an unsteered player's account of Latch and Low Water. That human
  gate remains open even if the scripted route and captures pass. A fixed
  release visual is not evidence of a fighting autonomous companion.
- Run the repository's full Rust, coverage, benchmark, dependency, playtest,
  roster, soak and Godot gates before claiming implementation. Keep the
  unfiltered 90 percent coverage floor.

## Spend and release

Use local art and committed audio fallback; external API/cloud budget for this
slice is $0. Any paid asset or GCP test remains behind the written spend gate,
the $20 current-sprint ceiling and the $50 repository cap. Do not apply cloud
infrastructure. This plan is stacked after PR #270 for review, with no merge,
tag or release until capabilities 14 to 16 are integrated and the acceptance
gates are resolved.

## Progress

- 2026-09-27: Read-only server and lore audits traced the proximity-only
  objective, the encounter completion order, map preparation, `Use` validation,
  mission projection and accepted story beats. No billable service was used.
- 2026-09-27: The authored route now advances from ward arrival to guarded
  local Use at Latch's frame, then dock departure. An unknown encounter
  prerequisite or unreachable control fails map preparation. Focused server
  route tests cover bypassing the Crawler pack, early, remote and occluded
  presses, ward victory before release, duplicate use, wipe and late
  spectator state. A stale local-child test exposed the old spawn objective;
  it now asserts `ward_reached` and the still-active machine.
- 2026-09-27: The capability-17 M02 wire publishes `ward_secured` from the
  encounter's Complete state and `companion_released` from mission progress.
  Strict Rust, Godot and adapter readers validate the fact. M01 and arena
  capability requirements remain unchanged.
- 2026-09-27: A render-only ward sequence follows those server facts: machine
  quiet, local release, Latch opening a second occupied bay, then a list that
  names Low Water as the next recall target. A late reader reconstructs the
  final tableau; retry, skip and muted Voice keep keyed text. Independent
  review found an Escape conflict with an open match menu, now guarded and
  tested. The fixed figures are provisional, not a moving companion.
- 2026-09-27: The directed live M02 route passed all 17 states through dock
  departure on Windows with Godot 4.7.2 and the release server. The first
  attempt found that QA aimed below the real frame panel; the corrected route
  uses the authored use point and proves the prompt and actual F press.
  Inspected frames show the separate ward stop, the opened second bay and the
  corrected `NEXT: LOW WATER` list. This is scripted visual evidence, not an
  unsteered player's understanding.
- 2026-09-27: Workspace tests, format and Clippy passed. Unfiltered line
  coverage is 94.52 percent. The 16-bot deterministic benchmark passed with
  no tick-budget overruns on this Windows machine. Dependency policy, four
  live mode playtests and the 2/6/6/8/12/16 mixed roster across six maps
  passed. The roster saw one later spawn death on map 4, none at opening.
  The full Godot checker and all ten verifier self-test scenarios passed.
  External asset API and cloud spend remains $0.
- 2026-09-27: The 120-second rotating-map soak passed with four agents, four
  bots and two spectators. Nine samples held 20.00 Hz with no tick-budget
  overrun, a 0.56 ms lifetime tick p99 and 37.8 to 38.4 MiB RSS on this
  Windows machine. These local numbers do not prove internet hosting capacity.
- 2026-09-27: The standard 32-state visual tour passed and refreshed the
  published player-facing stills. Its initial attempts exposed a respawn and
  weapon-selection race in the QA harness; the tour now waits for server spawn,
  reissues a bounded weapon choice and checks authoritative aim before capture.
  Four unedited ward frames and capture provenance are in
  [`docs/screenshots/m02-latch/`](../screenshots/m02-latch/README.md).
- 2026-09-27: The final pinned Godot checker passed after the QA fix, and the
  entire Rust workspace built in release mode with the locked dependency set.
- 2026-09-27: Draft PR #272 passed combined stack CI against main: Rust test,
  benchmark, roster, 90 percent coverage gate, release build, Godot, soak,
  audit, packages and Windows/macOS portability. Its base was restored to the
  Crawler draft for focused review. The integration check ran on commit
  `d9335fc`; this plan-only status update has no gameplay changes.
- An unsteered player review of the rescue and Low Water meaning remains an
  acceptance gate after the engineering slice.
