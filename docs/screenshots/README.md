# Screenshots

The `tour_*.png` files are the arena tour captured by
`tools/qa_tour.sh --publish` with Godot 4.7.2-stable and a loopback server.
The `m01_*.png` files are Recall Notice gameplay from
`FRAGR_QA_BOTS=0 FRAGR_QA_MAP_FILE=server/maps/m01-recall-notice.json FRAGR_QA_MANIFEST=res://qa/m01-rooms.json tools/qa_tour.sh`.
Inspect every frame before it is named in the README. A nonblank image is not
proof of good art. A player-visible change refreshes the README stills that
show that surface, in the same change. The Windows taskbar icon is still the
Godot mark and is not one of these frames.

`m01_intake_16x9.png`, `m01_balcony_16x9.png`, `m01_stacks_16x9.png`, and
`m01_dispatch_16x9.png` were captured 2026-09-21 on Windows from the completed
13-state room tour and inspected 2026-09-22. Intake shows a Sweeper in the
hall with the Tack in hand. The balcony shows the reserved opening toward the
custody lift. The stacks are dark steel on green tile. Dispatch is bone walls
on a dark floor after the fight. Sorting and dispatch still share the bone
wall. These are the development mission, not a finished art pass.

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
| `m01_intake_16x9.png` | Recall Notice intake, Sweeper in the hall, Tack in hand |
| `m01_balcony_16x9.png` | Records balcony, opening toward the custody lift |
| `m01_stacks_16x9.png` | File stacks, dark steel walls, green tile floor |
| `m01_dispatch_16x9.png` | Dispatch after the fight, dark floor, bone walls |
| `tour_multiplayer_16x9.png` | App multiplayer page after GET /status. One host, not a web list. |
| `tour_menu_16x9.png` | Retro boot menu |
| `tour_profile_16x9.png` | Callsign, reticle, and weapon bob |
| `tour_records_16x9.png` | Persisted arena observation, exact attack denominator and incomplete-session status |
| `tour_settings_16x9.png` | Saved controls, including sensitivity, inversion, turn speed, and weapon bob |
| `tour_difficulty_16x9.png` | New-run Assisted, Standard and Severe choices |
| `tour_first_person_16x9.png` | Human first person |
| `tour_spectator_16x9.png` | Spectator through a fighter's eyes |
| `tour_combat_follow_16x9.png` | Optional chase view |
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

## Historical captures

Numbered stills (`01_*` through `22_*`) record earlier builds and are retained
for comparison. They are not current gameplay evidence. In particular, the
v0.13.0 jammer and first-person stills show the earlier HUD, weapons, and geometry.
Their old capture workflow is documented in `../plans/tip-screenshots.md` and
`../plans/tip-stills-hangar-guns.md`.

`mood/` contains concept plates, never gameplay proof. Keep concepts and historical
screenshots out of the README's current-build gallery.
