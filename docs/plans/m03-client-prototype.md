# Scheduled Service client prototype

**Status:** shipped in [PR #314](https://github.com/blisspixel/fragr/pull/314), 2026-09-30. Integration belongs to
[m03-scheduled-service-prototype.md](m03-scheduled-service-prototype.md).
**Spend:** planned and actual $0.

The later [M04 prototype](m04-notice-to-vacate-prototype.md) supersedes this
plan's initial live capability 24, rules revision 2 and save version 4 contracts.
The later [M05 prototype](m05-no-forwarding-address-prototype.md) requires
capability 26 and rules revision 3 for current authored missions; compatible
historical saves upgrade explicitly to version 6. Earlier receipts below retain
the versions actually tested.

## Goal and scope

Present the authoritative Scheduled Service mission through the shared mission
wire, with strict map-bound validation, readable objective prompts, a clearly
labeled standalone development launch, durable M03 resume and reader-paced text
arrival and departure. Preserve the M01/M02 contracts and personal saved run.
This is a full input-playable prototype, not M03 acceptance or finished art.

Own `mission_state.gd`, a dedicated `m03_mission_state.gd`, `mission_hud.gd`,
`boot_menu.gd`, `local_match.gd`, `player_record.gd`, `story_scene.gd`, their
focused harnesses and UIDs, M03 catalog keys in `world.en.po` and `story.en.po`,
and new text scene manifests. The coordinating lane owns GameManager, NetClient,
world presentation, sky, plan index and protocol-envelope integration. The
server lane supplies exact MapInfo/progress fields and Shoot objective action.
No edits to another lane's files without a handoff.

## Architecture and protocol

Mirror server facts at the client boundary. Bind progress to the validated M03
map, objective definitions and bounded counts. Reject unknown fields, invalid
finite geometry, inconsistent targets and party prompts, backwards progress or
identity changes within an attempt. Permit an authoritative retry to reset the
mission while ticks, run allowance and attempt identity remain coherent.

Use gameplay capability 24 only for the new local M03 child. Earlier local
requirements remain unchanged. Standalone development uses no run-mode argument
and preserves the personal save. Durable resume accepts M03 ready/pending states
from the existing server preview and keeps body choice and remaining continues.
The next pending edge is Notice to Vacate, without a playable M04 claim.

Reuse mission-ready, continue and interaction controls, and ScenePlayer's input
release barrier. Car release and mast damage stay server-owned. HUD cards stage
briefly on objective or retry changes; legal local prompts remain while issued.
The mast objective instructs shooting, never fabricates a use command.
Arrival/departure manifests contain keyed reader-paced text with no paid assets.
Departure plays once after the server already reports departure.

## Verification and success criteria

Pinned Godot 4.7.2 focused checks cover malformed MapInfo/state, valid real wire
fixtures, cross-map identity, bounded targets/counts, progress monotonicity,
attempt/run rules, party prompts, HUD staging, localization/device glyphs,
spectator/recovery views and M03 records. Fake-process tests prove exact child
arguments, readiness version, cancellation and isolated development/resume.
A real owned local child is tested after the rebuilt server is available,
using isolated settings/run storage and no mouse capture.

The client lane runs the full checker and its failure-detection tests. The
coordinating lane owns inspected M03 route captures:
arrival, Jammer motion, automatic car release, mast fall, final fight, boarding,
departure and retry. Keep exact focused commands/results below, with logs under
`.agents/m03-buildout-20260930/`. No human feedback prerequisite, but fresh-player
comprehension, balance, par and final story/art acceptance remain unproven.

## Non-goals

No simulation, movement, wire-control duplication, save writer, paid narration,
new engine/API version, drivable train, M04 gameplay or public deployment.

## Work record

- Final bounded correction: test authoritative captive-distance gait and its
  150 ms resting timeout, including repeated and malformed samples, and the
  registered intact/fallen pod shell bounds and materials. Emit the keyed
  Mara warning through the existing corner notice feed on the first observed
  positive-to-zero mast-health transition per run/attempt. Preserve its latch
  across redundant MapInfo clears, reset on retry/disconnect, and remove the
  misplaced departure warning page. No narration or blocking overlay is added.
  Run the full pinned Godot checker and its failure-detection harness after
  these corrections; the server binary remains untouched during the tour.
- Read canonical `l03-scheduled-service.md`, shared prototype plan and current
  mission/local/record/story seams before implementation.
- M03 is currently only a pending menu destination; map/state, ready previews,
  launch capabilities and record scope have strict M01/M02 assumptions.
- Ownership approved 2026-09-30. Independent launch/record/text groundwork can
  proceed while the server lane finalizes the M03 observation schema.
- Implemented the exact capability-24 M03 development/resume launch, pending
  M04 menu edge, record admission, reader-paced arrival/departure manifests,
  localized signs/objectives, strict M03 map/state helper and staged HUD.
- The agreed wire uses `m03.mast_shutdown` to distinguish the prepared fallen
  world. Original pod aim stays bound while a fallen map may move that solid.
  Mast health zero must match the shutdown world. The next legal goal is the
  registered locomotive Use, with the living ready party aboard.
- Integration review caught a moving-captive mismatch before the real route
  tour: release initiates authoritative walking, not an immediate jump to safe
  feet. Released feet now stay within 0.05 metres of the clamped held-to-safe
  segment; endpoints share height within 0.01. Held feet stay registered. Tests
  cover intermediate walking, held start, safe endpoint, diagonal off-segment,
  elevation and out-of-map refusal. Server controller mirrors the tolerance.
- Focused checks used the pinned Windows Godot 4.7.2 console binary:

  ```powershell
  & 'C:/GitHub/_toolchains/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path client --script res://scripts/test_m03_mission.gd
  & 'C:/GitHub/_toolchains/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path client --script res://scripts/test_m03_local.gd
  ```

  Both passed with exit 0, individual PASS markers and no error logs. The real
  local test launched the development menu's owned ephemeral-port M03 server,
  reached its reader-paced briefing, held fire through dismissal, observed no
  readiness until release, then entered authoritative play. It preserved an
  existing isolated `run.json` byte-for-byte and stopped only its own child.
  Automated pointer ownership remained visible throughout.
- `test_local_match`, `test_frontend`, `test_player_records`, `test_story_scene`,
  `test_mission`, `test_m02_mission` and `test_scene_player` also passed with
  exit 0 and PASS markers. The scene-player harness intentionally warns on its
  invalid-scene fixture; no script/runtime errors occurred. Logs live under
  `.agents/m03-buildout-20260930/test_*.log`.
- The M03 harness tests actual NetClient JSON admission and ordered mast-world
  handoff, static-contract rejection, monotonic progress, retry/allowance,
  legal party prompts, staged owner/spectator HUD, device/locale changes and
  recovery. Yard checks inspect both captive atlases, finite server feet,
  restraints, authoritative-distance gait, the 150 ms resting cutoff, repeated
  and malformed movement samples, registered active/fallen pod bounds and
  materials, and malformed/non-M03 cleanup. No standalone route promises a
  durable save.
- Mara's warning now appears immediately after the first observed authoritative
  positive-to-zero mast-health transition in each attempt: "Mara: Low Water,
  this is Mara. Go now." It uses `WORLD_M03_MARA_WARNING` and the existing
  three-second campaign corner notice feed, away from the aiming area. Actual
  NetClient transition tests prove duplicate/fallen MapInfo suppression,
  retry/disconnect reset, no invented warning on a late join and notice expiry.
  The departure manifest retains train and home pages; its misplaced warning
  page and unused catalog key were removed. Spoken narration remains unbuilt.
- Read-only GameManager review confirms shared scene dismissal, action clearing
  and readiness release ownership. Arrival does not replay on a mast world
  replacement; retries keep the existing per-attempt readiness channel.
- Final focused `test_m03_mission` passed after the gait/pod and Mara corrections
  with exit 0, its PASS marker and no errors. The gait-rest test waits on the
  same monotonic milliseconds used by the renderer rather than assuming an
  engine scene timer proves real elapsed time.
- Full client checks ran without rebuilding the server during the route tour:

  ```powershell
  $env:GODOT_BIN='C:/GitHub/_toolchains/godot/Godot_v4.7.2-stable_win64_console.exe'
  & 'C:/Program Files/Git/bin/bash.exe' tools/godot_check.sh
  & 'C:/Program Files/Git/bin/bash.exe' tools/test_godot_check.sh
  ```

  Both exited 0. The full checker recorded `Godot checks: PASS`: clean import,
  148 script checks and all 66 harnesses, including the actual owned local M03
  child, boundary/presentation checks and existing M01/M02 regressions. The
  verifier passed all ten injected success/failure cases, including missing
  PASS, error-plus-PASS, failed exit, long output and retained verbose failure
  identity. Logs: `.agents/m03-buildout-20260930/godot-full.log` and
  `godot-verifier.log`. `git diff --check` passed.
- Independent final still review found a literal `{menu}` placeholder in the
  M03 departure card. The catalog now uses the existing `{pause}` token, which
  resolves to `ESC: RETURN TO MENU` on keyboard and `MENU: RETURN TO MENU` on
  the tested gamepad layout. The corrected catalog was imported before the
  final route capture.
- The same review found that plain departure cards waited for another mission
  packet to refresh their device label, while the server suppresses unchanged
  mission packets. `MissionHud._process` now calls its existing `_refresh` on
  an input-device revision. M02/M03 tests switch keyboard to gamepad and back
  after one departure apply, without another packet, and prove the stage
  countdown, visibility and authoritative facts stay unchanged. Expired
  objective cards stay hidden. Focused M01, M02, M03 and input-glyph harnesses
  all passed with exit 0 and their PASS markers.
- Final checks after both corrections used the same pinned commands above.
  Both exited 0: clean import, all 148 script checks, all 66 harnesses and
  `Godot checks: PASS`; the verifier passed all ten scenarios. No error/failure
  lines or active owned test harnesses remained. `git diff --check` passed.
  Current logs: `.agents/m03-buildout-20260930/godot-departure-device-final.log`
  and `godot-verifier-device-final.log`. The interrupted pre-switch run is
  retained as `godot-departure-pre-switch-partial.log`, not PASS evidence.
- Read-only rendered review inspected the standard tour contact sheet and
  full-size eyes, chase, combat, menus, records and shot/impact strips. Final
  standard capture coordination recorded 32 states with PASS. The final
  `.agents/qa/m03-yard-eleventh/` receipt recorded 21 states, all 22 required
  enemies, three released cars, mast health zero, secured train and a complete
  human record with zero deaths. The corrected departure frame visibly shows
  `ESC: RETURN TO MENU`, and boarding retains its legal `F` prompt. Mara's
  warning, registered red pod and changed fallen world were also inspected.
- Remaining visual limits are explicit: world-space arena names can be partly
  occluded by cover, and close views of the current cuboid Latch can obstruct
  much of the first-person picture. Captive strips show settled liberated
  poses, not held-to-safe walking quality. The solo Jammer strip remains weak
  travel evidence; its committed firing still shows the resolved pulse.
  Boarding/departure are static state/text evidence, not train animation.
  Stills do not prove interpolation cadence or performance. Inspected M03
  evidence is the compatibility renderer on the reported AMD 780M device.
- Source is frozen. The shared prototype plan owns integration and acceptance.
  The cleared input route is authoring evidence, not fresh-player comprehension,
  ten-minute pacing, difficulty acceptance, finished narration or the authored
  scene-animation gate.
