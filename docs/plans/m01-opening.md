# Recall Notice opening and party readiness

Status: in flight, 2026-09-20. Task: [#192](https://github.com/blisspixel/fragr/issues/192).
Depends on the local campaign entry and reliable initial map delivery already
released in v0.27.0 and v0.27.1. No opening is playable yet.

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
