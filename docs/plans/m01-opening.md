# Recall Notice opening and party readiness

Status: shipped in [#193](https://github.com/blisspixel/fragr/pull/193) and
[v0.28.0](https://github.com/blisspixel/fragr/releases/tag/v0.28.0), 2026-09-20.
Task: [#192](https://github.com/blisspixel/fragr/issues/192).
Depends on the local campaign entry and reliable initial map delivery already
released in v0.27.0 and v0.27.1. The text opening is playable; integration and
release evidence is linked from the task. Finished scene art and narration are
not part of this implementation claim.

## Outcome and story

Deliver the five beats in [M01's storyboard](../campaign/m01-recall-notice.md#opening-storyboard):
home workshop, Latch choosing to help, Voss's reassuring address becoming a
demand for obedience, the recall, and pursuit to Annex 67. The companion remains
captive after M01; its transfer record identifies the correction destination.
Use body-neutral framing, the established cast and faction palettes. Keep the
small bureaucratic joke before the seizure. No Inheritance contact, wipe reveal,
simulation hint or radio exposition belongs in this opening.

Provide reader-paced localized panels with next/back/skip, keyboard/controller
navigation, a persistent recap/objective, and replay from the campaign menu.
Essential text stays outside pictures. Missing or muted optional audio never
blocks comprehension or progression. The same scene can later accept finished
art and narration without changing mission state.

## Authority and canonical seams

The introduction cannot cover a live fighter with an unprotected local overlay.
Extend `mission.rs`, its protocol types and Session's existing command path with
mission/attempt-scoped readiness. Revise campaign admission capability explicitly;
preserve legacy arena admission. Shared wire agents use `MissionClient`; MCP gets
the same explicit slow operation and public mission facts.

- Initially admitted participants finish or skip independently. Combat starts
  when all current members acknowledge. Disconnect removes that member's wait.
- After play starts, late readers cannot pause the party. A pending reader stays
  at the safe entry and cannot act, claim supplies, trigger encounters, be
  targeted/damaged or prevent a real party wipe.
- Readiness cannot be withdrawn for protection. Keep acknowledged members across
  retries, prune departed IDs and clear queued gameplay input on acknowledgment.
  Stale, mismatched and spectator acknowledgments do nothing.
- A reader can continue through a party retry. Finishing acknowledges the
  currently observed attempt; retries do not restart the presentation.

Use one MissionRun readiness state and one participation predicate across sim
movement, equipment, combat and encounter paths. Do not introduce a second pause
or invulnerability subsystem. Preserve geometry-before-mission delivery and
client boundary validation when fields or capabilities change.

## Client presentation

One opening presenter owns paging and completion. GameManager owns network
handoff and blocks gameplay input while awaiting mission state, reading or
waiting for the party. The old timed LoadingCard cannot provide this behavior;
suppress it for the campaign opening. Early input handlers must let the presenter
consume dismissal without turning the same input into a shot or a hidden menu.

Replay instantiates the same presenter without any server launch or readiness
callback. Reuse MenuTheme, translations, settings and existing audio routing.
The mission HUD remains the canonical objective display. Test expanded text and
glyphs; pseudolocalization alone does not establish CJK or RTL support.

## Art and spend

Use consistent references and the existing developer pipelines. Do not freeze
unapproved faces or voice casting from a stray candidate. The user reported
$14.69 prepaid Higgsfield credit with automatic top-up disabled; that is an
account snapshot, not a live balance result. Reconcile the outstanding Clerk
reservation before further paid generation, then price exact requests and use an
explicit small cap. Existing credits do not authorize top-ups or overages.
No paid call is required for readiness implementation or player runtime.

## Verification and completion

- Deterministic tests for partial/final readiness, disconnect, invalid and stale
  messages, input clearing, retries, late readers and every participation path.
- Real wire proof with human, agent and spectator roles and a four-person party.
  Preserve existing gate, inventory, combat and departure assertions.
- Client checks for real input events, paging, skip, replay without mutation,
  text expansion, missing audio, waiting, reconnect and unexpected server exit.
- Inspect every panel, skip recap, waiting state and first-person handoff. Exercise
  both M01 approaches, MCP/agent operation and the six-map roster. Keep strict
  Rust, unfiltered coverage, Godot, cross-platform CI and published gallery gates.

Full mission population, checkpoints and final campaign completion remain separate
work. Update M01, campaign scene production, protocol, adapter documentation,
roadmap and this plan to the behavior actually proved before releasing.

Primary APIs checked 2026-09-20: Godot's [localization](https://docs.godotengine.org/en/stable/tutorials/i18n/internationalizing_games.html)
and [Control](https://docs.godotengine.org/en/stable/classes/class_control.html)
contracts. Use keyed translations, named placeholders, containers and translation
refresh. No dependency or engine change is required.

## Current implementation

The English script and interface copy live in `client/i18n/story.en.po`.
`CampaignOpening` presents all five beats with keyboard/controller buttons,
scrollable expanded text and offline replay. The first visual pass left excessive
empty space; inspected revision uses a centred, bounded reading panel and larger
body copy. No finished illustration, voice or movie is claimed.

Gameplay capability 5 adds `mission_ready` and each party member's `ready` flag.
One server participation predicate covers input, equipment, pickups, hit tests,
enemy targeting and encounter activation/reset. Readiness survives retries and
cannot be withdrawn. Shared wire controllers acknowledge automatically; MCP has
an explicit tool. Paid decisions wait for active participation.

GameManager blocks input until valid mission state, local completion, dismissal
release and server acceptance. The old timed card is omitted for missions. A
queued state without our party identity does not consume the acknowledgment slot.
Controller tests exposed missing menu accept/cancel bindings; explicit bindings
now preserve keyboard arrows and support controller paging and text scrolling.

Local evidence on 2026-09-20:

- 705 Rust tests pass, including fresh-party reset and Tripoint placement
  regressions, with two existing ignored asset generators. Strict Clippy passes.
  Unfiltered workspace line coverage is 95.81 percent.
- Four real human/agent sockets wait for their final reader. Spectators, stale
  attempts and old capability-4 clients cannot activate the party. Existing gate,
  movement, inventory, both M01 approaches and shared departure assertions remain.
- Eight verifier fault scenarios pass. The initial 27-harness run failed profile
  cancellation because the new cancel binding omitted physical Escape; the local
  summary missed that log failure before Linux CI caught it. The binding and
  keyboard/controller cancellation regression are fixed; all 27 harnesses then
  pass with verifier exit 0. The checker now ends with an aggregate result,
  preventing a tail of individual passes from obscuring an earlier failure.
  An inspected OpenGL/AMD 780M lifecycle run also passes with a second real agent reader,
  waiting HUD, held dismissal, rejoin, leave, unexpected server exit and cancellation.
- The 21-state default gallery was regenerated and inspected, including shot and
  impact strips. Opening and waiting stills live in `docs/screenshots/prototypes/`.
- The 16-state rendered M01 tour passes and was inspected: pickups, fights, both
  stair routes, record use, gate opening and prototype departure. It explicitly
  skips the opening through the same presenter and waits for server admission.
- Release build, dependency policy and the 16-bot, 1,200-tick deterministic CPU
  benchmark pass. Four network clients complete the smoke with eight frags and
  no spawn deaths. These establish neither large-server capacity nor final art.

The final combined build's six-map mixed reflex/planner roster passed the
unchanged assertions:

| Map | Seed | Clients | Frags | Spawn deaths |
|---|---|---|---|---|
| Arena Duel | 67 | 2 | 6 | 0 |
| Compliance Yard | 42 | 6 | 26 | 0 |
| Directive 17 Substation | 19 | 6 | 17 | 4 |
| Sector 9 Transit Hall | 42 | 8 | 33 | 4 |
| Reclamation Gulch | 42 | 12 | 41 | 5 |
| Tripoint Works | 42 | 16 | 52 | 3 |

These short runs prove the existing acceptance checks, not spawn safety or fun
at every density. Retain the spawn-death evidence for the next arena balance pass.
The first integration run, 35519428024 at `4f77f71`, failed the menu-cancel
regression on all three platforms and the Linux Tripoint roster (10 spawn deaths
among 51 frags). All five jobs pass on the cancellation/fresh-party fix at
`af0c2e3`, run 35520042833. Tripoint also failed on unchanged main, so that green
sample does not close the recurring defect. The separate
[spawn-safety repair](tripoint-spawn-safety.md), task #194, is included before
final integration rather than relying on an unexplained retry.
Logs and intermediate captures are under `.agents/m01-opening-*` and
`.agents/m01-tripoint-*`; final roster reports are in
`.agents/playtest/m01-tripoint-roster/`. Earlier failed and superseded evidence
is retained. Integration CI is recorded on the linked pull request; shipped
status belongs to its release record.
No new paid generation was needed. Issue #186's intermittent
exit retention remains open; clean local runs do not establish its cause or fix.
