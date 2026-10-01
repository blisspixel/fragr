# Screenshots

The `tour_*.png` files are the arena tour captured by
`tools/qa_tour.sh --publish` with Godot 4.7.2-stable and a loopback server.
The `m01_*.png` files are Recall Notice gameplay from
`FRAGR_QA_BOTS=0 FRAGR_QA_MAP_FILE=server/maps/m01-recall-notice.json FRAGR_QA_MANIFEST=res://qa/m01-rooms.json tools/qa_tour.sh`.
Inspect every frame before it is named anywhere. A nonblank image is not
proof of good art. The README embeds four files and no more: `tour_menu_16x9.png`,
`m01_intake_16x9.png`, `tour_multiplayer_16x9.png`, and `tour_combat_follow_16x9.png`.
A player-visible change refreshes the one of those four that shows the surface,
in the same change. The other files in this directory stay as tour evidence.
The project tour runs the engine binary. Packaged desktop games use the original
game icon checked by the release workflow; these stills do not prove taskbar icons.

The standard tour was regenerated and inspected on 2026-09-30 after participant
timeline interpolation, spectator camera smoothing, near-camera shot-effect
clipping and all five campaign prototype integrations. All 32 states passed; thirteen
selected stills were published locally by the wrapper. The capture receipt is
`.agents/qa/m05-standard-modal-final/manifest.json`. Menus, settings, weapon views,
participant bodies, world lighting and watched combat were inspected after capture.

The `m05_*.png` gallery is the No Forwarding Address development prototype,
captured and inspected on the same pinned Windows/OpenGL/AMD Radeon 780M setup.
Its final 25-state ordinary-input route cleared all 21 guards without a death,
visited three secret locations, released three workers and confirmed all three
physically aboard before departure. Three secret supplies were claimed: tank
armor, service Shells and a service Grenade refill. The market medkit stayed
available at full health. The player lost 100 armor and no HP. A normal
jump boarded the tram; 99 supported samples showed equal 4.800017 m rider and tram
travel. The Heavy fired four actual rounds before the Rifle clear. The passenger
dialog was corrected above the HUD and verified with physical cancel/reopen/confirm.
Receipt: `.agents/qa/m05-rooftops-sixth/manifest.json`;
[plan](../plans/m05-no-forwarding-address-prototype.md).

| File | Inspected state |
|---|---|
| `m05_roof_crossing.png` | Roofs and crane walk after the opening clear, not a live Notary phase |
| `m05_tank_secret.png` | Actual second-tank supply and readable `/6` clue |
| `m05_paint_bay.png` | Real chassis cover and ordinary counted-grenade discovery |
| `m05_grenade_flight_strip.png` | Real launch, tracked flight and descent beyond the chassis; matching explosion is occluded by cover and has no hits |
| `m05_worker_release.png`, `m05_worker_motion_strip.png` | Three freed workers visibly walking from the opened workshop |
| `m05_service_secret.png` | Accessible room-facing service clue and actual supply detour |
| `m05_tram_ride_strip.png` | Real supported ride after trench clearance, with moving background |
| `m05_heavy_firing.png` | Actual Heavy firing, red lamp and resolved incoming trace |
| `m05_passenger_review.png` | Three actual aboard statuses and readable F/ESC controls above the HUD |
| `m05_departure.png` | Server-confirmed carrier departure after fresh physical confirmation |

The named windup frame faced away from the Heavy, so it is not published as a
visible tell. Required windup is typed server evidence; the firing still visibly
shows the attacker. M05's other phase probes are post-clear views. Earlier M04
frames provide separate live Notary presentation evidence. These stills establish
an accurate-aim authoring route, not final art, fresh-player timing or difficulty
acceptance, and remain separate from the four README images.

`jammer_windup_16x9.png`, `jammer_launch_16x9.png`,
`jammer_defeat_16x9.png` and `jammer_pulse_strip.png` were captured and inspected
on 2026-09-30 with Windows, Godot 4.7.2-stable, OpenGL compatibility and an AMD
Radeon 780M. They come from the completed eight-state input-driven
`client/qa/jammer-range.json` tour on `server/maps/test/jammer-range.json`.
The frames show the committed tell, open transmitter and live pulse, then the
collapsed emitter. The twelve-frame lateral strip shows the orange point
advancing and growing as it passes the camera. This is an original development
combat range. The separate Scheduled Service development route now reuses this
enemy; these range frames do not show that mission or establish a finished art pass.
The receipt is `.agents/qa/jammer-buildout-polished/manifest.json`;
[the buildout plan](../plans/campaign-and-feel-buildout.md) records checks and
limitations. Earlier distant motion and failed captures remain diagnostic-only.

The `m03_*.png` gallery shows the input-playable Scheduled Service development
prototype on the same pinned Windows/OpenGL/AMD Radeon 780M setup. Its passed
twenty-one-state route confirms all twenty-two enemies, three optional car
releases, mast shutdown, both secret pickups and deliberate locomotive use.
[The authoring plan](../plans/m03-yard-authoring.md) records the exact manifest,
failures, corrections and renderer receipt. These images are separate from the
four README stills and do not establish fresh-player or difficulty acceptance.
Current receipt: `.agents/qa/m03-yard-eleventh/manifest.json`.

The `m04_*.png` gallery shows the Notice to Vacate development prototype on the
same pinned Windows/OpenGL/AMD Radeon 780M setup. Its final 23-state route cleared
all 28 guards without a death, opened the clinic, released both patients and used
the roof departure. All three secret locations were reached; two pickups were
claimed and the meal medkit remained available at full health. The player lost
125 HP and 100 armor over the attempt and finished at 100 HP and 50 armor.
The receipt is `.agents/qa/m04-market-ninth/manifest.json`;
[the authoring plan](../plans/m04-market-authoring.md) records failures and limits.
These frames establish an accurate-aim authoring clear, not fresh-player pacing,
difficulty acceptance or final art. They are separate from the four README stills.

| File | Inspected state |
|---|---|
| `m04_arrival.png` | Actual Low Water first-person arrival and ordered first objective |
| `m04_notary_windup.png` | Raised Notary's committed tell above the market |
| `m04_notary_firing.png` | Actual locked attack with the Rifle aimed at the raised body |
| `m04_notary_motion_strip.png` | Timed actual drone observation frames |
| `m04_clinic_patients_strip.png` | Grounded released patients on their bounded route |
| `m04_clinic_care.png` | Open clinic and patient outcome after physical Use |
| `m04_market_water.png` | Actual shallow runoff, grate and repair detail in the market |
| `m04_awning_secret.png` | Armor secret reached by the ordinary stair route |
| `m04_court_balcony.png` | Court height, residential backdrop and cleared combat space |
| `m04_roof_departure.png` | Actual server-confirmed departure with ESC return-to-menu binding |

The final aftermath was inspected after correcting camera-depth clipping: the
large near-camera sky fragments are gone. Water motion/depth and repair-texture
lighting have separate rendered regressions; a still alone cannot prove them.

| File | Inspected state |
|---|---|
| `m03_yard_arrival_16x9.png` | Daylight carriage frontage at the actual first-person arrival |
| `m03_jammer_firing_16x9.png` | Committed emitter launch with its resolved orange pulse |
| `m03_car_liberated_16x9.png` | Freed captive at the third car and server-confirmed three-car counter |
| `m03_mast_target_16x9.png` | Registered red pod aimed at from the ordinary precision stairs |
| `m03_mara_radio_16x9.png` | Mara's immediate corner warning after authoritative shutdown |
| `m03_mast_fallen_16x9.png` | Fallen mast collision world on the signal-box roof |
| `m03_signal_secret_16x9.png` | Actual secret pickup reached around the fallen geometry |
| `m03_train_boarding_16x9.png` | Low Water control with a legal local Use prompt |
| `m03_train_departure_16x9.png` | Server-confirmed departure with the resolved keyboard menu binding |

The timed solo-Jammer observation strip is context; it does not establish pulse
motion. Car-release stills show released figures, while validation/gait harnesses
prove their bounded server-foot presentation. The train views show the stationary
control and outcome, not moving vehicle physics or a rendered cinematic. Primitive
locomotive geometry and repeated surfaces remain prototype art.

`m01_intake_16x9.png`, `m01_balcony_16x9.png`, `m01_stacks_16x9.png`, and
`m01_dispatch_16x9.png` were captured and inspected 2026-09-24 on Windows,
OpenGL compatibility, AMD Radeon 780M, from the completed 13-state room tour
after the first look-pass lighting increment. Rooms are clearly lit by a warm
base light with brighter pools under the strip-light fixtures: intake shows the
counters and lockers with a pistol in hand; the balcony looks toward the custody
lift; the file stacks are dark steel racks with red warning strips on green
tile; dispatch is enamel walls with the red pinline. The earlier flat, evenly
lit versions of these four frames are in git history before this change.
Black-and-red Union enemies were checked in the same rooms with
`client/qa/m01-enemies.json`. These are the development mission, not a
finished art pass.

The tour stills in this directory were republished in the same change: the
arenas sit under a warmer, stronger sodium sun with a slightly lower ambient
floor and a warmer haze, so cover throws readable shadows. The menus are unchanged. Frame
times and the quality and world-pixel comparison are in
[`../plans/look-pass-boomer.md`](../plans/look-pass-boomer.md);
`FRAGR_QA_MANIFEST=res://qa/look-perf.json` and `res://qa/m01-perf.json` (with
the M01 map file) repeat them.

`m01_secret_shiv_16x9.png` is the `secret_shiv_found` state of
`FRAGR_QA_MANIFEST=res://qa/m01-exploration.json`, captured and inspected
2026-09-24 on Windows (OpenGL). The player stands in the confiscation alcove's
south pocket looking back into the bay: the Shiv is in hand, and the corner
feed reads the medkit, the Shiv pickup and `SECRET FOUND`. The held blade is the
draft's single idle pose; the thrust is a scale and slide of that pose.

`prototypes/local-campaign-menu-20260920.png` shows the inspected Recall Notice
launch option. `prototypes/local-campaign-entry-20260920.png` is the actual M01
entry after a menu-owned server starts, captured on Vulkan after the controls
card clears. These show the development slice, not a complete campaign.

`prototypes/m01-opening-20260920.png` shows the new text opening.
`prototypes/m01-party-waiting-20260920.png` shows a real human participant ready
while an agent is still reading. Both were captured and inspected on Windows,
OpenGL compatibility, AMD Radeon 780M using `test_local_campaign.gd`. All five
text panels, skip handoff and offline replay were checked. Illustrations and
narration remain unfinished. The two older local-campaign stills above predate
the new opening and remain historical lifecycle evidence.

`prototypes/m01-continue-20260920.png` and `m01-exhausted-20260920.png` show
the current solo death choice and exhausted run on Windows, OpenGL compatibility,
AMD Radeon 780M. The real local-launch recovery harness walks into Clerk fire,
spends three continues through ordinary input, checks restored fists/position/facing,
then proves the fourth death ends the run. All seven death/retry frames were
captured; the two result states above were inspected and retained. The older
party-waiting still describes the dedicated development host, not local solo rules.

`prototypes/m01-records-20260920.png` is the inspected 14-state expanded records
route, captured on Windows, OpenGL compatibility, AMD Radeon 780M. The run
confirms twenty named guards and mission departure through ordinary inputs.
The rooms and characters remain development art, with final pacing, persistence
and fresh-player acceptance outstanding. Source manifest: `client/qa/m01-records.json`.

| File | View |
|---|---|
| `m01_intake_16x9.png` | Recall Notice intake under its fixtures, pistol in hand, counters and lockers |
| `m01_balcony_16x9.png` | Records balcony, opening toward the custody lift |
| `m01_stacks_16x9.png` | File stacks, dark steel racks with red warning strips, green tile floor |
| `m01_dispatch_16x9.png` | Dispatch after the fight, enamel walls with the red pinline |
| `m01_secret_shiv_16x9.png` | The secret Shiv found in the confiscation alcove and held in hand |
| `tour_multiplayer_16x9.png` | App multiplayer page after GET /status. Host example is 127.0.0.1:6767. |
| `tour_menu_16x9.png` | Retro boot menu |
| `tour_profile_16x9.png` | Callsign, reticle, body choice with its preview, and weapon bob |
| `tour_records_16x9.png` | Persisted arena observation, exact attack denominator and incomplete-session status |
| `tour_settings_16x9.png` | Saved controls, including sensitivity, inversion, turn speed, and weapon bob |
| `tour_difficulty_16x9.png` | New-run Assisted, Standard and Severe choices |
| `tour_first_person_16x9.png` | Human first person |
| `tour_spectator_16x9.png` | Spectator through a fighter's eyes |
| `tour_combat_follow_16x9.png` | Watched Arena Duel fighter in chase view |
| `tour_body_human_16x9.png` | Close still of a fighter the server says is human, in free colours at hit-volume height |
| `tour_body_synthetic_16x9.png` | The same framing on a fighter in a synthetic body, an embodied agent |
| `tour_arena_overview_16x9.png` | Server geometry with industrial surfaces and scenery outside the playable boundary |
| `tour_shot_strip.png` | Twelve frames of an acknowledged shot |
| `tour_rail_impact_strip.png` | Single local rail impact on the floor, sampled through spark expiry |

The full tour also checks rail/scatter selection, server-confirmed upward and
downward aim, return to spectating, the
multiplayer page, all four settings tabs, and settings inside the live match
overlay and the service record. Captures use isolated settings and history files. The local manifest records actual
map, round, role, weapon, camera/server yaw and pitch, dimensions, flash visibility, and
strip sample times. Observations are copied at capture time so a later disconnect
cannot clear earlier evidence. Full-size `*_shot.png` frames preserve impact detail before
strip reduction. Intermediates live in
`.agents/qa/`. Set `FRAGR_RENDER_DRIVER=vulkan` to check that rendering path;
OpenGL compatibility is the tour default. This is renderer evidence on the
recorded host, not a GPU vendor certification or a load benchmark.

`FRAGR_QA_MANIFEST=res://qa/graphics.json FRAGR_RENDER_DRIVER=vulkan tools/qa_tour.sh .agents/qa/graphics`
compares actual resolution, quality and upscaling states at a fixed 1920x1080
window size. Repeat with `FRAGR_RENDER_DRIVER=opengl3` to inspect fallback.
The receipt records the active renderer, device, world scale, reconstruction and
MSAA state. Fullscreen/windowed transitions belong to `test_render_quality.gd`;
this capture deliberately keeps its window dimensions fixed.

`FRAGR_QA_MAP=3 FRAGR_QA_MANIFEST=res://qa/records.json tools/qa_tour.sh .agents/qa/records`
waits for an actual arena completion before opening its saved record. Its idle
human participant is not a win or skill benchmark. Compare the captured server
record with the persisted entry; the campaign recovery harness checks four
deaths and three continues as one failed run.

For a separate live movement check, run:

```bash
FRAGR_QA_BOTS=0 FRAGR_QA_NO_ROUND_EVENTS=1 FRAGR_QA_MANIFEST=res://qa/movement.json tools/qa_tour.sh .agents/qa/movement
```

It sends a sub-frame Space tap and walks ordinary inputs up/down the Arena Duel
stairs and off a ledge. The manifest records server feet and camera height;
`jump_peak.png` captures the actual hop. Timed round events are explicitly disabled
so a boss cannot kill the test player halfway through the route. This is a
movement check, not a combat playtest. Do not use `--publish` with this manifest.

M01's focused intake/stair traversal tour uses `res://qa/m01.json` and a validated
local map file. Commands and scope are in [`server/maps/README.md`](../../server/maps/README.md).
It walks both stairs and the balcony underpass through live input, now clearing
the draft opening encounter along the way. `m01-discovery.json` checks ammunition
and reload; `m01-encounters.json` and `m01-maintenance.json` capture the two combat
approaches. The main tour now observes both enemy types firing before fighting
back and records their actual sprite frames with the server phases. Enemy artwork
remains under review. The transfer record, gate and shared departure now use
server-confirmed state; the complete mission remains unfinished. These
runs do not replace the release gallery or prove a finished mission.

`m01-facility.json` adds focused walking/combat views of intake signs,
locker banks and the maintenance route. `m01-records.json` covers the expanded
records wing, sorting, dispatch and transfer controls in fourteen states. Its
ordinary input driver can fight during travel and search authored room routes;
named guard deaths remain evidence after corpse cleanup. A respawn cannot hide
a failed run. Short F presses must actually advance mission state before
capturing the opened gate and result.
Check glyphs, panel placement,
lighting and enemy contrast with both rendering paths. Localized text must fit
the panel; the complaint notice targets bureaucracy, not captive suffering.

Use `res://qa/weapons.json` with the same zero-bot practice settings for close
walking strips of every viewmodel. Their base must remain below the screen
through the whole stride. Use `FRAGR_QA_MAP=2` through `6` with
`FRAGR_QA_MANIFEST=res://qa/roster.json` for alternate-map overview, fighter eyes,
and a human joining/firing in live bot combat. `FRAGR_QA_SOLO_BROADCAST=1` selects
Episode 0; do not combine it with quiet practice. These alternate manifests do
not publish the README gallery. Record actual states and inspect the captures.

The current arena pass uses authored pixel-grid materials and industrial scenery.
First-person views retain normal fighter scale; optional broadcast views keep
their distant silhouette boost. These are current playable visuals, not evidence
of completed campaign environments or final character animation.

`ctf_arena_duel_union.png`, `ctf_arena_duel_free.png`, `ctf_directive17_union.png`
and `ctf_directive17_free.png` are the 2026-09-30 home-flag frames from
`client/qa/ctf.json` on Arena Duel and Directive 17, OpenGL, AMD Radeon 780M.
Both flags are home, the corner reads the capture score, and each stand is in
that map's back third. They are not a human or spectator verdict, and they are
not part of the four README stills.

## Historical captures

Numbered stills (`01_*` through `22_*`) record earlier builds and are retained
for comparison. They are not current gameplay evidence. In particular, the
v0.13.0 jammer and first-person stills show the earlier HUD, weapons, and geometry.
Their old capture workflow is documented in `../plans/tip-screenshots.md` and
`../plans/tip-stills-hangar-guns.md`.

`mood/` contains concept plates, never gameplay proof. Keep concepts and historical
screenshots out of the README's current-build gallery.

The `heavy_turret_*.png` files come from
`FRAGR_QA_BOTS=0 FRAGR_QA_MAP_FILE=server/maps/test/heavy-turret-range.json FRAGR_QA_MANIFEST=res://qa/heavy-turret.json tools/qa_tour.sh`
and the baked atlases, captured and inspected 2026-09-24 on Windows. The
`union_recolor_*.png` files compare Clerk and Sweeper cells before and after the
black and red Union recolor, plus two frames from the M01 encounter tour. The
[plan](../plans/heavy-sweeper-and-turret.md) describes what each one shows.
