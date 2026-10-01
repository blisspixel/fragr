# M06 client prototype

**Status:** in-flight, 2026-10-01. Parent: [M06 Port of Entry](m06-port-of-entry-prototype.md).
**Spend:** $0 new charges. The separately approved M06 batch consumed 252 included
audio credits, bringing round usage to 945 credits with a conservative $4
equivalent reserve. This lane makes no service requests. Original lunar textures
are baked locally at no cost.

## Goal and boundaries

Present the authoritative Port of Entry prototype as an inhabited lunar port,
with strict mission facts, truthful retained Earth choices, ordinary local entry,
readiness and departure. Preserve M01-M05 map bytes, gameplay, equipment and
recording. Root owns the Rust server, v7 save migration and once-only Episode II
refill. The map lane owns authored M06 geometry and its ordinary-input tour.

No low-gravity, vacuum damage, pressure puzzle, runtime dependency,
named character casting, moving ship or final character reference is introduced.
Tern and the impound ship remain static presentation until movement is proven.

## Contract and integration

Map 1006 uses `port_of_entry`, capability 27 and rules 3. Earlier authored missions
retain capability 26 admission. The new client advertises 27. `m06` geometry has
six Arrival objectives, a separately registered service Arrival, departure Use,
boarding and companion_start. Required IDs are freight_cleared, rail_lane_cleared,
loading_cleared, turret_cleared, customs_cleared and exit_cleared, then
party_departed. The optional service ID is prisoner_route_marked.

Mission facts have exact completed/current binding, prisoner_route_marked and
immutable carried recall cars, patients, photograph count, released workers and
evacuated workers. The current objective is omitted only on departure. Validate
finite bounds, exact prefixes, monotonic same-attempt facts and retries. Released
workers are empty or all three known identities; evacuated workers are a unique
subset. Preserve historical order. The client never supplies campaign outcomes.

Use the existing LocalMatch preview/process owner, BootMenu Practice selector,
GameManager readiness release barrier, MissionHud and ScenePlayer. Pending M05
Continue Run plays M06 arrival once; an existing M06 entry does not replay it.
New manifests use localized text fallback and preserve existing audio/text pairs.

Lunar materials, fixtures and backdrop use registered map geometry and existing
surface/shader/light seams. Safe-family windows use inspection_glass solids.
Substantial accessible props require authoritative solids. A bounded lunar
boundary exception exposes authored window views without offering an escape or
floating landmarks above an arbitrary wall. Original textures are baked locally
from GDScript and imported nearest. Turret presentation must use actual server
head yaw, without the existing extra baked search oscillation.

## Verification and completion

Before any native, Godot or GPU work, obtain the coordinated runtime lease.
Focused checks cover malformed/duplicate/stale facts, exact geometry binding,
retry/reset, retained arrays, M02 glass preservation, HUD/device glyphs, Practice,
scene skip/fallback and presenter cleanup. Actual local children cover a strict
historical v6 pending M05 exit, exact equipment/Grenades/body/outcome carry,
once-only three-continue refill, saved-entry resume and owned cleanup.

Rendered review requires actual quiet arrival, inhabited glass, Earth/depot/static
ship, real Rail discovery and resolved long shot, genuine Turret sweep/charge/
shot/cancellation/flank, secrets and optional marker, departure and menu layouts.
Inspect motion as well as stills in Compatibility, including readable shadow
and transparent sorting. Run the full pinned Godot checker and verifier, then
the authored M06 tour and standard published tour after final source freeze.

Fresh-player pacing, difficulty briefs, par mastery, final residents/Tern art and
moving impound staging remain acceptance gaps until separately proven. Record
actual commands, failures, fixes, counts and inspected evidence here before
marking the client work implemented.

## First implementation receipts

Source now includes the strict M06 helper/dispatcher, client capability27 and
M06-only launch readiness, the fifth compact Practice selection, pending M05
arrival selection and pending M07 text, retained records, objective/optional
marker HUD and the once-per-attempt Tern customs notice. The owned native
`test_m06_local` is ready but has not run until the matching release lease.
It uses a strict v6 pending M05 fixture with zero old continues, two grenades,
unsorted released workers and an aboard subset, then checks actual promotion,
the arrival release barrier, exact carry and already-spent M06 reopening.

The original `tools/bake_moon_details.gd` produced four 128-pixel textures with
source/output hashes. The lunar presenter keeps household possessions, meal
table, neighbours, a warm bounded task light and labelled recycling tray behind
registered impassable pressure glass. Earth, gantry, static ship and custody
depot sit outside gameplay bounds; generic arena walls are hidden only for this
explicit lunar venue, retaining every authoritative solid view.

Pinned 4.7.2 headless import and focused checks passed with exit 0 and clean logs:
`client-test_m06_mission-focused-final.log`,
`client-test_m06_presentation-focused-final.log`,
`client-test_local_match-focused-final.log`, `client-test_frontend-ready.log`,
`client-test_qa_combat-baked.log`, `client-test_story_scene-baked.log`,
`client-test_campaign_audio-ready.log` and `client-test_map_geometry-baked.log`,
under `.agents/m06-buildout-20261001/`. The new ambient WAV initially imported
with compression; its committed import now retains original 16-bit stereo
24kHz PCM and a complete six-second forward loop. The audio harness decodes
positive energy, matches exact narration captions/receipts, observes actual
final completion, preserves the reader's final hold and exercises missing
assets on both new manifests. No human listening judgment is claimed.

The Compatibility/AMD780M Union bake passed in `client-union-bake.log`, with
all four atlas/source manifests refreshed. Selected Turret front/profile idle,
walk, full charge and floor death cells were inspected in the ignored
`turret-selected-poses.png`: idle/walk preserve the same head yaw, while full
charge lights the red sensor ring and barrel coils. The older harness expected
a fictitious Turret gait; it now asserts same-yaw pixel equality and a distinct
real profile, while retaining all other gait, clipping, death, freshness and
readability checks. `client-test_enemy_animation-final-focused.log` passed.

These are source, asset and isolated checks. Real mission movement, long Rail
shots, cover cancellation/rear Turret combat, native migration/refill and actual
world screenshots remain pending. Source inventory is 180 scripts and 84 harnesses.
All 180 scripts passed check-only parsing with exit 0 in
`client-all-parse.log`; no native launch or full checker is claimed by that pass.

Independent review found one rotated crater rim corner inside the half48 square.
The cosmetic radius now accounts for the square diagonal and the complete rim
footprint. `client-m06-landmark-bounds.log` passes projected world bounds for
every exterior box at half48 and the minimum half2 fixture; no authoritative map
or collider changed. Final cancellation captions must rely on actual observed
cover/charge facts, rather than inferring cancellation from an authored route.

## Native carry and final verification progress

`client-m06-local-actual-compact-fixture.log` passed with exit 0 and a clean log.
Three owned local launches proved development-entry save isolation, strict v6
pending M05 promotion with zero old continues, the actual arrival release barrier,
one refill to three continues, exact health/body/gear/two grenades and unsorted
retained worker outcomes, one byte-preserving archive, and a spent M06 reopening
without a second refill or arrival. Owned children and isolated run files closed
and cleaned up. The first reopening fixture had reserialized parsed JSON integer
fields as floating literals; the strict server correctly refused those bytes.
The corrected fixture preserves the real writer bytes and changes only its one
compact integer `remaining_continues` value. Production validation is unchanged.

The first full client run parsed 180 scripts and passed 83 of 84 harnesses. Its
sole failure was an older M05 presentation assertion expecting four Practice
entries. The fixture now checks all five entries and explicitly selects M05 at
its unchanged index 3; all readability, focus, story and effect checks remain.
`client-m05-selector-five-final.log` passed. Earlier failed logs remain retained.

The bounded `QaTurret` observation helper and existing `QaCombat` caller now
require a fresh named Turret windup, actual registered blocked sight, an early
twelve-tick recovery, unchanged health/range and consecutive snapshots through
the original shot deadline without that Turret's resolved shot. The explicit
lesson flag is strictly typed and requires one named Turret; other probes retain
their behavior. Independent review corrected omitted empty shot arrays and
accepted signed health for unrelated Heavy bodies and corpses. Focused receipts
`client-qa-turret-final.log` and `client-qa-combat-final.log` passed cleanly with
exit 0. Candidate rejection reasons remain observable; only a completed positive
cycle proves cancellation. Source inventory is now 182 scripts and 85 harnesses.

The prior-tick review then tightened causality: server enemy decisions occur
before movement emits the new snapshot. A successful receipt must therefore
retain blocked sight, living in-range participation and unchanged Turret health
on the immediately preceding same-cycle Windup snapshot. Entering cover only on
Recovery, or previously losing range, cannot prove cover caused cancellation.
The corrected helper and caller passed in `client-qa-turret-causal-final.log`
and `client-qa-combat-causal-final.log`, preserving the original shot deadline.

The checker verifier passed all ten failure-injection scenarios with exit 0 in
`client-checker-verifier.log`. `client-m02-carry-final.log` passed the existing
actual carry wrapper with exit 0. Its first attempt ran before the new helper
class was imported and failed parsing; no actual carry child started on that
attempt. A partial final checker was stopped during parsing before native
harnesses began, to incorporate the independent prior-tick cancellation review.
Its `client-full-check-final.log` is interrupted evidence, not a PASS receipt.
Rendered mission evidence remains pending until the actual tour finishes and
its images and motion sequences are inspected.

## Rendered iteration receipts

`client-all-parse-causal-final.log` passed all 182 scripts with exit 0 and a
clean log. The first rendered wrapper failed before server startup because
`--map-file` conflicts with `--solo-broadcast`; the supported authored launch
uses `--map-file`, `--campaign-run`, zero bots, seed 42 and standard difficulty.
The failed startup log remains preserved. The second supported run was
intentionally stopped after two dock states for an inspected Earth-art fix;
every owned native and renderer PID was verified and closed.

The original Earth bake now uses recognizable simplified continent silhouettes
and irregular bright cloud belts over blue ocean, retaining nearest 128-pixel
transparency and the terminator. Drawing, dust and pressure-shell pixel branches
remain unchanged. `client-moon-earth-rebake-final.log`,
`client-moon-earth-import-final.log` and `client-moon-earth-focused-final.log`
passed with exit 0 and clean logs; the new texture was inspected. The earlier
typed-array bake diagnostic and consequent stale-source refusal remain retained.
The map lane corrected only the QA camera aim to the actual Earth position.

The third actual tour ran under `.agents/qa/m06-port-third/`. Its inspected
Earth still visibly shows the original planet above the weapon through freight
pressure glass, framed beneath the gantry's top beam. The stage filename does
not establish that Earth is physically above that beam. The inhabited glass room
also visibly shows two provisional residents, meals, belongings and the labelled
recycling tray. The dock declaration is angled in its arrival still; that frame
does not prove its sign copy is readable.

The third route failed after sixteen states at the rear Turret approach. It did
prove an actual first shot and a later charge cancellation: blocked deciding
Windup tick 3108, twelve-tick Recovery at 3109, and no same-Turret shot through
original deadline 3129, verified through 3130. It climbed all six treads to y3,
then the focused walking helper oversteered off the gallery's x=-21 edge. The
Turret remained alive; the required death/rear-arrival gate correctly failed.
Owned tour children closed. This partial tour is not a mission PASS.

The existing QA direction helper now selects the nearest of eight ordinary input
directions, using the 22.5-degree split instead of the old 0.2 projection cutoff.
`client-qa-route-shot-final.log` passed a pure shared live-movement regression
that recreates the actual gallery start and continuously tracked Turret, reaches
the rear waypoint and stays at y3. Cardinal/diagonal behavior remains covered.
Combat retains at most 64 actual participant ShotResults plus tick, with an
observable omission count; stale snapshots, inactive observation, absent actor
rosters and later packet mutation cannot rewrite those facts. The next tour can
measure actual Rail origin-to-impact distance. The authored 58.25-meter spacing
is separate from an actual clear after the Sweeper pursues the participant.
No enemy movement, collision, phase, health, shot spread or gameplay changed.
