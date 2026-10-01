# Scheduled Service prototype

**Status:** shipped in [PR #314](https://github.com/blisspixel/fragr/pull/314), 2026-09-30. Local prototype increment on
`feat/campaign-and-feel-buildout`, after the verified local Jammer increment.
M03 mission acceptance and package release evidence remain separate work.
**Spend:** planned and actual $0. Nick's $20 external-charge cap continues to
apply to this development round, within the repository's $50 total cap.

The later [M04 prototype](m04-notice-to-vacate-prototype.md) supersedes this
plan's initial live capability 24, rules revision 2 and save version 4 contracts.
The later [M05 prototype](m05-no-forwarding-address-prototype.md) requires
capability 26 and rules revision 3 for current authored missions; compatible
historical saves upgrade explicitly to version 6. Earlier receipts below retain
the versions actually tested.

## Goal and contract

Build an input-playable M03 Scheduled Service on the accepted
[level 3 treatment](../campaign/l03-scheduled-service.md), the existing mission
control channel and authoritative Jammer. Preserve the M01/M02 authored bytes
and compatible saved runs. Nick requested continued development without a human
feedback prerequisite; human acceptance remains separate evidence.

The prototype has an original daylight freight yard with two tracks, carriage
flanks and roof routes reached by ordinary stairs. It introduces the Jammer
alone, then combines it with established guards. After clearing the mast
defenders, the player shoots the registered transmitter pod. Resolved server
pellet impacts damage it; neither a client collision nor a use command does.
The mast changes to a precomputed fallen world. A final Union push precedes
explicit locomotive departure with the living ready party aboard.

Latch opens optional recall cars after their local guards are cleared and the
party reaches the car. These releases never block the main route or departure.
Bound car count and authoritative captive presentation. Do not require an NPC
to squeeze through a doorway or arrive on a timer. The train departure uses the
existing story player, not a new driveable vehicle simulation. Arrival and exit
copy use existing canon without resolving the proposed missing-morning story.

## Ownership

- Server lane: `protocol/mission.rs`; strict M03 authoring and prepared worlds in
  `maps/authored.rs`, `maps/authored/m03.rs`, `maps/runtime.rs`, `maps.rs`;
  mission runtime/controller and focused tests; `sim.rs` resolved-impact hook;
  `encounters.rs` and the existing companion seam only as needed for M03 Latch.
  Own `docs/plans/m03-server-prototype.md`.
- Client lane: strict M03 validation helper; `mission_state.gd`, `mission_hud.gd`,
  `boot_menu.gd`, `local_match.gd`, `player_record.gd`; existing ScenePlayer
  manifest validation and new reader-paced M03 arrival/departure manifests;
  focused harnesses and `world.en.po`/`story.en.po` M03 keys. Own
  `docs/plans/m03-client-prototype.md`.
- Map lane: `server/maps/m03-scheduled-service.json`; M03 input-driven QA
  manifests and map-specific evidence. No server/client boundary edits or
  translation-file edits. Coordinate exact identifiers with the server lane and
  words with the client lane. Own `docs/plans/m03-yard-authoring.md`.
- Coordinating lane: persistence and local launch (`mission/run_file.rs`,
  `run_file/store.rs`, `mission/recovery.rs`, `local.rs`, `run.rs`, `main.rs`);
  global protocol envelope/MapInfo producers and consumers; adapter/brain/tool
  integration; GameManager/NetClient, M03 world presentation and daylight preset;
  README, roadmap, index, this plan, verification and inspected captures.

Use explicit handoffs before editing another lane's files. Shared global format
runs wait for file freezes; focused checks may run during implementation.

## Architecture and protocol

Add `MissionId::ScheduledService`, strict M03 map geometry and progress, and a
shoot objective on the shared mission observation/control path. M03 requires
gameplay capability 24 for every role. Earlier M01/M02 minimums and campaign
difficulty revision remain unchanged. Geometry changes resend MapInfo before
mission facts using the existing ordering seam. Prepare and route-check only
two mast worlds before readiness; optional car presentation does not create
combinatorial collision worlds. Every required approach, supply, enemy and
landmark must remain reachable in both worlds.

The existing save already records M02 awaiting `scheduled_service`. Promote that
edge under the writer lock, preserving run ID, body, difficulty, health, armor,
weapons, ammo and remaining continues; clear old-map supply claims and establish
the M03 attempt baseline without an episode refill. Retry restores the exact
entry and resets mast, encounters and car releases without rewinding process
ticks, input sequence or inventory revision.

Retain the optional liberation outcome at M03 completion for the planned M04
edge, `notice_to_vacate`. If this adds a saved-document field, introduce explicit
version 4 and bounded version 3 upgrade while retaining version 2 M01 migration.
Archive old bytes before locked replacement; failure keeps the previous save
recoverable. A fresh durable run still starts at M01. Standalone M03 is clearly
labeled a development route and does not silently overwrite the personal run.

## Non-goals

No completed-M03 acceptance, ten-minute pacing or finished art claim; no M04
gameplay, ladder physics, driveable train, public hosting, transport rewrite,
new provider, paid narration or generated asset batch. The story's first-run,
par, difficulty brief and secret gates remain open until evidenced. Record the
actual Jammer roster, since the accepted text has inconsistent ordinal counts.

## Verification and success criteria

Seeded authoritative tests prove real pod hits, early-shot refusal, intervening
cover and actor occlusion, optional-car independence, party readiness and
deliberate departure, stale presses, retries and capability admission ordering.
Strict authored tests reject bad targets, regions, references and broken routes.
Save tests prove M02 promotion, outcome retention, allowance conservation,
compatible migrations, isolated restart and failed replacement recovery.

Both wire readers, the adapter and reference brain understand M03 through the
same readiness/continue/Action tools. Client tests prove malformed-state refusal,
map-bound identities/targets, monotonic progress, retry reset, HUD and localized
prompts, records, reader-paced scenes and owned child launch/cleanup. Run the
full required Rust and pinned Godot checks, multiplayer regressions and soak.
Regenerate and inspect the standard tour and an actual M03 route, including
pulse motion, automatic car release, mast shutdown and departure. Keep logs
under `.agents/m03-buildout-20260930/` and captures under `.agents/qa/`.

## Work record

- Starting tree contains the completed prior local buildout and no unrelated
  user edits; preserve it on the existing branch.
- Parallel source research identified strict two-mission assumptions in save
  promotion, MapInfo, controller validation, local readiness, HUD and records.
- A name containing `recall` selects the indoor sky before the existing yard
  match. M03 needs an explicit daylight venue match and a regression test.
- Existing movement supports stairs, not ladders. Roof routes must use real
  authoritative geometry with ordinary movement.
- No paid or cloud operation is planned or has occurred.
- Implemented save version 4 with strict optional completed-M03 car outcomes.
  Explicit version 3 upgrade accepts only its released M01/M02 stages, while
  version 2 M01 upgrade remains supported. An exact archive precedes locked
  replacement. Current M03 completion records live exit equipment and optional
  liberated IDs while leaving the M04 edge pending.
- M02 promotion retains the same run, body, difficulty, HP, armor, owned weapons,
  ammunition and remaining continues. It clears previous-map claims, establishes
  the M03 attempt baseline and gives no episode refill. A real isolated local
  child test upgrades a released v3 M02 save, restarts M03 twice and verifies the
  original archive is retained exactly once. Failure-injection tests preserve
  recoverable bytes when replacement fails.
- M03 map validation, shared controllers, adapter observations, reference brain,
  playtest and Godot consume the same capability-24 mission contract. Earlier
  campaign admission requirements and difficulty revision 2 are retained.
- Original daylight presentation uses registered signs and existing material,
  participant and enemy assets. The registered pod gets a readable red shell
  and intact/fallen status lamp. Optional captive silhouettes follow validated
  authoritative feet, animate from observed distance and return to idle at rest.
- Reader-paced arrival and departure reuse the existing story player and input
  release barrier. Mara's keyed warning appears once immediately after observed
  mast shutdown through the existing corner notice feed. There are no new paid
  images, narration calls or runtime dependencies.
- Rendered iteration exposed hut shortcuts, a rooftop-only search for a ground
  enemy and an unsafe postcombat diagonal across the roof gap. The final route
  uses the actual doorway and named ground flank. After roof combat, the
  ordinary drop to the central ground lane handles either a roof or already
  fallen player pose, then crosses south of the cars. The earlier ascent proves
  the roof stairs; this transition makes no stair-descent claim. Shared evasion
  forecasts unsupported or blocked strafes through the mirrored live movement
  step. Server preflight also checks consecutive declared walk, search and
  approach segments against both prepared worlds; it cannot prove every
  variable combat endpoint's next route.
- The mast trigger originally covered the whole yard width, activating its
  guards during the optional western hut stop. Narrowing it to the two eastern
  approaches preserves the intended recovery beat and keeps the fight local.
  Map bytes and rendered evidence are being rechecked after this authoring fix.

## Verification record

Logs are under `.agents/m03-buildout-20260930/` unless specified below. The
first full workspace test run passed before the final QA preflight and
completion-projection tests. Both added focused regressions, final format and
final workspace Clippy passed. Final unfiltered workspace coverage passed after
rendered process cleanup, including the complete test suite.
The completion projection specifically preserves authored save identity across
the fallen world and writes only actually released car IDs with the captured
live exit equipment.

| Check | Recorded result | Evidence |
|---|---|---|
| Workspace tests | PASS: final coverage run executed 1141 passing workspace tests, zero failed and three existing ignored; server 659 passed and local child 12 passed | `final-coverage.log`, `workspace-tests.log` |
| Unfiltered workspace coverage | PASS: 94.56 percent lines, 43982 total and 2391 missed; no exclusions | `final-coverage.log` |
| Workspace Clippy and format | PASS after completion-projection and expanded QA preflight additions | `final-clippy.log`, `final-fmt.log` |
| Full release workspace | PASS; final embedded-map rebuild includes narrowed mast trigger | `final-release-build.log` |
| Dependency licenses, bans and sources | PASS | `deny.log` |
| Pinned Godot checker | PASS: clean import, 148 script parses, all 66 harnesses, no errors; includes final shared combat driver, device-switch refresh and real local child/save checks | `godot-departure-device-final.log` |
| Godot checker failure detection | PASS: all ten scenarios, including bad exits, reported errors and missing harness markers | `godot-verifier-device-final.log` |
| Four multiplayer mode regressions | PASS: FFA, TDM, Rail Only and TDM Licence to Kill; completed rounds and zero open-spawn deaths | `playtest-*.log`, `.agents/playtest/m03-ci*.json` |
| Controlled CTF | PASS: real take and capture | `.agents/playtest/m03-ci-ctf-route.json` |
| Contested CTF | Combat and replication gate PASS, but zero takes/captures and a 0-0 clock finish; competitive completion remains unproven | `.agents/playtest/m03-ci-ctf.json` |
| Six-map roster wrapper | PASS: 2/6/6/8/12/16 mixed clients, zero open-spawn deaths | `.agents/playtest/m03-roster/*.json` |
| Standard rendered tour | PASS: 32 states, 13 locally published stills; contact sheet, menus, match and transient strips inspected | `.agents/qa/m03-standard-device-final/manifest.json` |
| M03 ordinary-input route | PASS: 21 states, all 22 named enemies, three car releases, both secrets, mast shutdown and deliberate departure; zero deaths | `.agents/qa/m03-yard-eleventh/manifest.json` |
| Final authored QA movement | PASS: all consecutive declared walk/search/approach segments in both mast worlds, including corrected train approach | `yard-input-preflight.log` |

The release benchmark uses exactly 16 bots, 1200 ticks, seed 42, `--bench-check`
and `--bench-assert` on Arena Duel. The soak uses the prescribed 120 seconds,
15-second samples, four bots, four agents, two spectators and map rotation.
These are local Windows x86_64 CPU/server measurements, not renderer, remote
network, large-server or GPU performance claims.

| Measurement | Result | Evidence |
|---|---|---|
| Benchmark session and encoding p99/max | 0.720895 / 3.2018 ms; zero over-budget ticks; deterministic replay accepted | `final-bench.log` |
| Soak cadence | 19.93 Hz observed; nine samples; ticks 47 through 2439 | `final-soak.log` |
| Soak lifetime tick p99/max | 0.95 / 4.65 ms; asserted health and delivery checks passed | `final-soak.log`, `.agents/soak/m03-final.ndjson` |
| Soak RSS | 38.5 to 39.1 MiB, maximum 39.2 MiB | `final-soak.log` |

The standard tour used Godot 4.7.2-stable, OpenGL compatibility on AMD Radeon
780M at 1280x720. Its actual receipt records the renderer/device. Docker's
desktop Linux-engine named pipe is unavailable on this host, so container checks
have no local pass claim. Infrastructure is unchanged; no cloud operation or
Terraform change occurred.

Independent client review found no concrete new wire, lifecycle, save-isolation,
warning, gait, camera or shot-expiry regression. Independent standard-tour review
confirmed the incoming-effect clipping fix and clean inspected menus/impacts.
It also recorded existing partial world-name occlusion behind cover in combat
follow and chase views as a future readability improvement. Still images do not
establish interpolation cadence or frame pacing.
Independent M03 review additionally records close Latch body occlusion in
ground-flank, hut and mast-fight views. The existing cuboid companion presentation
can cover much of the first-person view at close range. Companion spacing and
art readability remain polish work; this is an actor body, not the fixed
incoming-shot polygon defect.

The first complete M03 route passed all twenty-one states and all twenty-two
named enemies on Standard. It released all three cars, collected both secrets,
disabled the mast through resolved shots and deliberately departed. Its completed
human record counted twenty-one kills plus one resolved companion kill, zero
deaths, 205 HP lost and 100 armor lost across finite recovery. Final HP was 25
with zero armor. The optional office Shotgun route was topology-validated but
not visited. Receipt: `.agents/qa/m03-yard-ninth/manifest.json`.

Independent final image review caught a literal `{MENU}` on the M03 departure
card. The catalog used unsupported `{menu}` instead of the shared `{pause}`
token. Corrected that source and added exact keyboard ESC and gamepad MENU
departure assertions, then reimported the catalog and passed the focused M03
harness. Final review also found that unchanged departed packets leave a stale
plain-card glyph after device switching. The existing HUD refresh now updates
the card on device revision without restaging its timer. Focused M02/M03 tests
switch keyboard to gamepad and back after one departed observation, preserving
mission facts, visibility and countdown; expired objective cards stay hidden.
Final full client checks and the standard publish passed after these visible
fixes. The eleventh M03 route passed with the corrected keyboard card; the ninth
remains earlier route evidence.

The tenth route passed the mast and secret but died at the final train push.
Its east-side z25 waypoint activated the final watch before a long walk to the
western supplies. Shared preflight rejected a direct z23 crossover through the
mast platform. The final capture instead returns through the established mast
west corridor and z7.5 crossover, then approaches the unchanged train trigger
from the west. This avoids a tight edge crossing and passes movement in both
worlds. Guards, finite supplies, ordinary evasion and health remain unchanged.

The final twenty-one-state M03 tour passed with wrapper exit 0. It confirms all
twenty-two named enemies, three released cars, mast HP zero, both secrets and
deliberate departure. The final still visibly reads `ESC: RETURN TO MENU`.
Receipt: `.agents/qa/m03-yard-eleventh/manifest.json`. Owned-process cleanup
completed before the standard tour refresh.

| Standard authoring run | Human kills / total named deaths | Deaths | HP / armor lost | Final HP / armor | Secrets |
|---|---|---|---|---|---|
| Ninth, initial complete route | 21 / 22, one companion kill | 0 | 205 / 100 | 25 / 0 | 2 |
| Eleventh, corrected western train approach and departure token | 22 / 22 | 0 | 57 / 100 | 75 / 0 | 2 |

These accurate-aim routes are authoring evidence. Different arrival/combat timing
and the revised approach prevent a controlled difficulty or balance comparison.
They establish neither the ten-minute first-run target nor fresh-player pacing.

## Handoff

This bounded prototype meets its implementation gates: authoritative mast and
optional liberation, an ordinary-input complete route, existing mission control
integration, compatible M02 carry/retry and save recovery, strict client
boundaries, local launch, story text and inspected final captures. Final Rust,
Godot, multiplayer, benchmark and soak verification passed as recorded above.
The standard gallery remains thirteen published files, with only four embeds
in the README. The separate M03 gallery contains nine inspected states.

The next development rung stays in the roadmap's single Full build order:
refine M03 resource pressure, pacing, close-companion presentation and scene/audio
treatment alongside M04 Notice to Vacate construction. The shared mission,
continue, prepared-world and saved-run paths now support three playable
development levels; reuse them for the next one. Fresh-player comprehension,
difficulty acceptance, two-machine network feel, optional office Shotgun play
and finished story/art remain open evidence. The prototype does not make M04
playable or promote a completed campaign mission.

Final external spend is $0 of the authorized $20 round cap. No paid generation,
cloud apply, commit, push, PR publication, merge, tag or release occurred. All
owned verification processes were cleaned up. Container verification remains
unavailable for the recorded Docker daemon reason. No further source changes
are pending in this increment.
