# M06 client prototype

**Status:** implemented, 2026-10-01. Local integration verified; CI and release pending. Parent: [M06 Port of Entry](m06-port-of-entry-prototype.md).
**Spend:** $0 new cash charges. The approved M06 audio batch consumed 252 included
credits and the separate shotgun refresh consumed 30, bringing round usage to
975 included credits with a conservative $5 audio equivalent reserve. Six
approved image requests reserve $0.274 across possessions and story images,
with provider billing unconfirmed and the prior uncertain $0.107 retained.
This lane completed the separately capped two-image $0.160 story batch;
original lunar textures are also baked locally at no cost. No top-up or overage
was enabled.

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

### Fourth gameplay tour, shutdown correction and selected possessions

The fourth tour recorded all 25 states, all 21 named guards, the optional marker
and actual party departure under `.agents/qa/m06-port-fourth/`. Its participant
record retained zero deaths, zero HP loss and 90 armor loss. It failed the clean
log gate on two leaked Compatibility textures at shutdown, so it is not a clean
mission PASS. The resolved participant Rail shot at tick 1278 measured 52.8996
meters from actual origin to impact and killed the pursuing named Sweeper. The
58.25-meter authored starting separation remains separate seeded evidence.
The actual Turret cancellation receipt retained blocked Windup tick 3074,
Recovery 3075 ending 3087, original deadline 3085 and no same-Turret shot through
verification tick 3086.

The shutdown defect reproduced without a server in the real main scene.
Replacing its first sky before the first completed draw leaked two 256-pixel
radiance textures; delaying replacement until after that draw exited cleanly.
Pinned [renderer source](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/rasterizer_scene_gles3.cpp)
allocates the matching radiance and raw-radiance textures from a pending sky
queue. GameManager now keeps replaced environments alive through one completed
`frame_post_draw`, while applying the new venue immediately. Headless checks do
not wait for a draw; exit disconnects the callback and releases retained values.
`client-main-probe-retained-final.log` reproduces the formerly failing sequence
with clean exit 0. The existing presentation harness covers immediate rapid
replacement, one-draw release and the headless branch.

Three inspected 128-pixel personal textures now occupy the existing sealed
room's EarthDrawing, storage surfaces and a flush meal-table cloth. Runtime
copies live in `assets/environment/moon/possessions/` and bind the inspected
source hashes; the original offline drawing remains the missing-asset fallback.
The original four-texture bake and its manifest remain unchanged. The source
batch has a $0.114 equivalent reservation with provider billing not reconciled;
this possession integration made no generation requests. Nearest materials and lossless imports
without mipmaps preserve the existing pixel surfaces and world lighting.
`client-possessions-import-final.log`, `client-possessions-presentation-headless.log`
and `client-possessions-presentation-rendered.log` passed with clean exit 0.
The isolated room still `moon-possessions-isolated.png` visibly shows the distinct
paper drawing, repaired storage cloth and tabletop cloth with the provisional
residents. This is a presentation preview, not an in-play whole-map acceptance.

Six adjacent focused harnesses passed cleanly in
`client-post-sky-test_m06_mission.log`, `client-post-sky-test_jammer_audio.log`,
`client-post-sky-test_shot_effects.log`, `client-post-sky-test_render_quality.log`,
`client-post-sky-test_qa_combat.log` and `client-post-sky-test_qa_turret.log`.
Final whole-client checks and regenerated inspected tours remain pending until
the remaining contact, audio and presentation sources are frozen together.

Two selected story key images were added through the separately bounded
[M06 story image plan](m06-story-key-images.md). Actual arrival/transit scene
playback, frozen narration, missing-image text fallback, exact resource hashes
and nearest presentation passed focused checks. The inspected 1280x720 scene
frames show the impounded transport/Earth and transit view of town/depot; they
remain story illustration rather than playable-world or transport-motion proof.
The story batch reserves $0.160, bringing the combined new image reservation to
$0.274 with unknown provider billing. No cash/top-up or extra generation request
was made by this work.

### Final contact capture route correction

The first final-contact tour in `.agents/qa/m06-port-contact-final/` failed after
19 states at the north gallery waypoint `[18.5,3,31.5]`. The living dormant exit
Turret stands at `[18.5,3,32]`; actual feet stopped at `[18.49999,3,31]`, the
correct one-meter combined body radius. This is a failed route receipt, not a
clean mission PASS. Its shutdown log had no leaked-texture error.

The capture route now uses the supported inner gallery at x17, preserves the
exact Cells visit `[0,3,31.5]` and the original clear window stance and aims.
No geometry, enemy, contact rule, tolerance or pickup grant changed.
`client-gallery-contact-focused.log` passed cleanly with exit 0. The existing
combat harness reads the actual map and manifest, walks all four corrected legs
with shared movement and body contacts while remaining grounded, and reproduces
the former waypoint stopping at z31. A new full capture is required to establish
clean final-tour evidence.

The corrected final-contact tour in `.agents/qa/m06-port-contact-second-final/`
passed all 25 states with clean wrapper exit 0 and no engine or shutdown texture
errors. All 21 named guards were confirmed; the final participant record reports
20 kills, zero deaths, zero HP loss and 45 armor loss. Three secret locations were
visited, with one actual secret supply claim; full-health medkits remain available.
The resolved Rail kill at tick 1274 measured 52.015735 meters, while the authored
58.25-meter starting spacing remains separate seeded evidence. The actual Turret
cycle retained blocked Windup tick 3114, Recovery 3115 ending 3127, original
deadline 3135 and no same-Turret shot through verification tick 3136. A later rear
kill and shared departure completed the unchanged required gates.

The matching standard tour in `.agents/qa/m06-standard-contact-final/` passed
32 states, published 13 stills and exited cleanly. Both tours' owned server and
renderer processes closed before the final whole client checker started.
Root inspected and approved six actual M06 stills plus the fixed-view Earth
20-frame strip and its inspection tiles under `docs/screenshots/m06_*.png`.
Earth, the inhabited room, Turret poses/beam and the static impound view are
visible. The phase stills are observed samples, not continuous motion evidence;
the Earth strip is a fixed camera with occasional companion movement. The
subdued impound view retains coarse prototype geometry. Fresh-player teaching,
all difficulties, par and final character performance remain open.

The final pinned whole client checker passed with clean exit 0: all 184 scripts
parsed and all 86 harnesses produced their required PASS markers. Receipt:
`.agents/m06-buildout-20261001/client-whole-contact-final.log`. The current M04,
M05 and M06 actual local-child carry/preview/reopen harnesses passed against the
matching release server. All owned Godot, server and tour processes were closed
after verification. Root owns the final fault-verifier receipt, CI, release and
publication status. This is an implemented and locally verified prototype;
it does not complete the remaining fresh-player or mission-acceptance work.
