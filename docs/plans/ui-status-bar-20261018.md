# Status bar and reduced motion

Status: **implemented**, #412 within [#418](https://github.com/blisspixel/fragr/issues/418).
Reviewed presentation merged through [PR #421](https://github.com/blisspixel/fragr/pull/421).
Main CI and v0.88.0 publication remain the integration gate. A stalled Windows
main attempt requires the [bounded client checker repair](bounded-client-checks-20261018.md);
the same source passed PR CI and all three PR desktop package checks.
Base: the palette and typography work in [PR #420](https://github.com/blisspixel/fragr/pull/420),
merged at `8e406135ff46c6265559b34db26eb274bb65ccf9`.
Main CI 39126933200 passed and v0.87.0 is published with three verified desktop packages.
The canonical sequence remains
[Full build order](../ROADMAP.md#full-build-order).

## Goal and scope

Make health, armor, ammunition and match objectives readable at a glance,
without changing the server's outcomes or losing information during mode and
camera transitions. Use the retained icons, canonical palette and bundled
fonts. Spend is $0, with no asset generation or external billing.

Health, armor and ammunition use equal Black Ops One numerals. Health is bone
above 50, ember from 26 through 50, and danger red at 25 or below. Exact numbers
and clamped bars remain visible. Zero armor stays readable and quiet. A fresh
living local damage transition from above 25 to 25 or below gives one short
pulse. Initial synchronization, repeated snapshots and followed-player changes
must not produce it.

Ammunition retains EquipmentState's authoritative meanings: rounds in the gun,
reserve excluding all loaded magazines, pooled agent ammunition, unlimited
weapons, the one-round Rocket tube and finite Article Blade uses. EMPTY appears
when the selected weapon has zero usable shots, including an empty magazine
with reserve. Spectators never receive inferred private inventory.

The top left holds at most mode and short round state. Centered match facts
hold score, clock and objectives. Preserve all five modes, mutators, friendly
fire, limited lives, CTF carrier/bearing/distance/return facts, Sabotage living
pips and held Use, and all five Conquest sites and tickets. Solo Broadcast's
episode objective/progress/pressure remains distinct from MissionHud's campaign
objectives. Tab owns the full standings.

The known weapon card stays visible only with actual content, in the appropriate
spectator view. Followed identity, map and temporary input hints move into a
bounded context stack above the reserved vitals. Preserve Unicode names, side,
stance and known weapon, and the original hint expiry across input-device changes.

## Architecture and contracts

HUD owns presentation layout and accepted display facts. GameManager supplies
explicit campaign/match context and existing snapshots, replacing its direct
round-label visibility manipulation. Remove the guessed score increment in
HUD.show_frag when wiring the new score display; standings follow snapshots,
including zero-score team kills. This does not change scoring rules. The FFA
center names its local or followed participant explicitly and retains that
participant's last accepted score by ID through temporary snapshot absence.
It never calls the visible-player subset a complete match leaderboard. Clear
retained scores at round/session boundaries; Ended uses accepted result facts,
never a cleared zero or a revived active-round score. A free camera without a
subject shows the target and clock without inventing a leader.

Use one layout calculation for the center and lower-left reservations. Pass
available geometry to ConquestHud and header placement to SabotageHud; their
state owners remain unchanged. CombatFeed retains its current event behavior
until #413, with a single rectangle owner preventing campaign notices from
colliding with context and vitals. Existing results and warmup cards keep their
priority. The opt-in broadcast decoration reserves a header band instead of
covering new match text; it remains off by default. Measure the actual bottom
edge of visible decorations, including fallback badges reaching logical y140,
and apply that origin to text, feed, Sabotage pips and Conquest alike.

The canvas is 1920 by 1080 logical units at a 1280 by 720 window, with a 2/3
stretch. A proposed 900-unit center leaves room for the existing right feed.
The measured 24-unit font makes SERVER HALLS 201 units and NEUTRALIZING 192,
so five 180-unit cells cannot contain Conquest's text. Reflow into an ordered
three-plus-two arrangement where needed. CTF gets separate wrapping flag rows.
Measure content heights and relayout on content/viewport changes; do not scale
the entire CanvasLayer. The later HUD-scale preference builds on these seams.

Persist `accessibility/reduced_motion` in FragrSettings, default false, and expose
it in a shared Accessibility page in boot and match settings. The setting
suppresses decorative camera shake/zoom kicks, HUD scale pulses, weapon bob and
kick translation, Rocket reload dip, pickup bob and scene pan/zoom. Enabling it
cancels active motion and restores resting poses immediately. Damage numbers
keep a stationary fade and their lifetime. Preserve aim, scope, follow movement,
accepted attack/reload frames, throw/melee actions and all resource counts.
The saved head-bob choice survives the effective reduced-motion override.

Retain one owned tween per animated target. A replaced card or earlier delayed
expiry cannot hide a newer card. Do not call cancel_fire_juice to suppress
cosmetic motion, because that also retires accepted weapon actions. Rocket
reload motion observes muted deadlines without restarting an old reload when
motion is re-enabled. Active and newly created pickups and story players inherit
the preference, including the boot-menu replay. Shared-image story pages stay
at rest after cancellation; unrelated preferences never restart narration.

No wire, save, movement, combat, world-material, reticle or dependency change.
Event tiers, flash controls, team-contrast controls, HUD scaling, signature
moments and the README redesign remain their following bounded issues.

## Verification and acceptance

- Test HP 100/51/50/26/25/10/0, numeric/bar clamps, armor zero, actual critical
  crossings, healing, repeated snapshots, hydration, death, retry and follow
  changes. Check active-pulse cancellation and preference persistence.
- Retain inventory arithmetic and privacy tests. Exercise empty magazine with
  reserve, total depletion, reload, pooled/unlimited/melee states, explosives
  and vehicle seats. A synthetic 255|999 font specimen is layout stress only;
  it does not expand the validated inventory capacities.
- Exercise CTF to campaign to Sabotage to FFA transitions, absent rules and
  reconnect. No stale score, flag, objective, clock, pips or episode text remains.
  Check snapshot-owned standings after ordinary and team-kill notices, delayed
  notices after their snapshot, death/respawn, elimination, disconnect and Ended
  rehydration. Retained participant IDs must never alias duplicate callsigns.
- Verify actual camera target cycling and follow movement with reduction on;
  warmup/card replacement during animation; muted Rocket deadlines; live and
  new pickup rest heights; active story and boot replay cancellation; and
  shared-still page advances without stale motion restarting.
- Render simultaneous populated regions at 720p: long Unicode CTF carriers,
  mutators/lives and notices; five Conquest statuses plus feed; planted Sabotage
  with held Use; Solo Broadcast objective/pressure; campaign notices and hints;
  spectator eye/chase/free/eye transitions; and optional broadcast decoration.
  Assert text containment and inspect pixels, not only parent rectangles.
- Inspect full, 50, 25 and 10 health, empty/ammunition states, refreshed FFA/TDM/
  Sabotage captures, and ordinary-input play. Publish and inspect the complete
  tour, run the full client checker, obtain independent review, and converge
  through passing PR/main CI and verified desktop release packages.

Private pre-implementation fixtures establish candidate geometry only. They do
not establish live gameplay, physical-controller use, human accessibility
acceptance or hardware performance. Record implemented evidence below as it is
obtained, keeping those remaining gates explicit.

## Implementation and review evidence

The implementation uses `HudRegions` for center, context, feed and radio
reservations, and `HudScoreSubject` for the selected participant's accepted
score. The visible roster is not a complete match leaderboard. Mode owners
still supply their original facts. Conquest uses a three-plus-two site layout;
Sabotage retains its pips, charge timer and held-Use progress.

Independent review caught and resolved missing persistent arcade pressure,
invented zero clocks on untimed rounds, Ended losing final objective scores,
delayed preference visibility, and cancelled transient motion restarting when
re-enabled. The new regression harness covers these transitions. VehicleHud
publishes its measured panel boundary so radio sits above both vehicle controls
and the full ammunition/explosive stack. Nearby boarding reserves that same
stock region. Geometry is recalculated when its inputs change.

Rendered evidence uses Godot 4.7.2, Linux Xvfb, GL Compatibility and llvmpipe
(LLVM 23.1.3), at 1280 by 720 physical pixels. It proves presentation in that
renderer, not GPU performance or human accessibility acceptance.

- The published [33-state tour](../screenshots/tour-20261018-status-bar.json)
  was inspected as a contact sheet and at full resolution for gameplay,
  settings and resolved weapon-effect strips. The earlier tour's real accepted
  25-health Scatter capture is retained separately as
  [live health evidence](../screenshots/status-bar-20261018/live-25-health.png),
  with its [source manifest](../screenshots/status-bar-20261018/live-25-health.json).
- [TDM](../screenshots/status-bar-20261018/tdm.json) records watched and joined
  clients against six rule bots on Sector 9. [Sabotage](../screenshots/status-bar-20261018/sabotage.json)
  records a joined client carrying, walking to the site, holding Use to plant,
  then observing the accepted planted state and detonation. The latter is a
  solo mechanics capture, not contested-match or human-play evidence.
- The `fixture-*` stills in [the evidence directory](../screenshots/status-bar-20261018/)
  are explicitly synthetic layout cases. They show full/50/25/10 health with
  bars, equal ammunition numerals and EMPTY, long Unicode CTF carriers plus
  notices, five Conquest sites, campaign context, broadcast fallback badges,
  and nearby/hot-gunner/aircraft panels with radio. Counts use valid inventory
  limits. These stills are not simulated mission completion.
- The [Accessibility page](../screenshots/status-bar-20261018/24_settings_accessibility.png)
  exposes the same persisted draft setting in boot and match menus. Focused
  checks pass for camera cancellation, accepted attack frames, muted Rocket
  deadlines, pickup rest poses, shared-story-image cancellation, live settings,
  score retention and mode transitions.

The final capture review also caught the Sabotage result card overlapping the
new centered status. Result and warmup cards now suppress the center, Sabotage
widgets and Conquest sites without discarding accepted facts. New Conquest
snapshots remain current behind the card and its expiry restores the region.
Regression tests cover both modes and the restoration.

The first live iteration exposed radio overlapping enlarged ammunition; the
single region owner and populated vehicle fixtures now prevent that collision.
The earlier full checker also caught test doubles and assertions still using
the old feed geometry owner; these were updated to exercise the new seam.
The final full checker passed all 584 checks, including 187 harnesses. Rust
formatting and all ten Godot-verifier failure-injection scenarios pass. Focused
checks also cover same-mode MapInfo handoffs clearing stale objectives, clock,
lives, pressure and Solo Broadcast state. Release convergence remains in progress. No service
credits or cash were consumed. Human feel and physical-controller acceptance
remain separate from synthetic input and rendering checks.
