# Screenshots

The `tour_*.png` files are the current local build captured by
`tools/qa_tour.sh --publish` with Godot 4.7.2-stable and a loopback server.
Inspect them after every refresh. A nonblank image is not proof of good art.

| File | View |
|---|---|
| `tour_menu_16x9.png` | Retro boot menu |
| `tour_profile_16x9.png` | Callsign, reticle, and weapon bob |
| `tour_settings_16x9.png` | Saved controls, including sensitivity, inversion, turn speed, and weapon bob |
| `tour_first_person_16x9.png` | Human first person |
| `tour_spectator_16x9.png` | Spectator through a fighter's eyes |
| `tour_combat_follow_16x9.png` | Optional chase view |
| `tour_arena_overview_16x9.png` | Server geometry with industrial surfaces and scenery outside the playable boundary |
| `tour_shot_strip.png` | Twelve frames of an acknowledged shot |
| `tour_rail_impact_strip.png` | Single local rail impact on the floor, sampled through spark expiry |

The full tour also checks rail/scatter selection, server-confirmed upward and
downward aim, return to spectating, the
multiplayer page, all three settings tabs, and settings inside the live match
overlay. Captures use an isolated settings file. The local manifest records actual
map, round, role, weapon, camera/server yaw and pitch, dimensions, flash visibility, and
strip sample times. Full-size `*_shot.png` frames preserve impact detail before
strip reduction. Intermediates live in
`.agents/qa/`. Set `FRAGR_RENDER_DRIVER=vulkan` to check that rendering path;
OpenGL compatibility is the tour default. This is renderer evidence on the
recorded host, not a GPU vendor certification or a load benchmark.

For a separate live movement check, run:

```bash
FRAGR_QA_BOTS=0 FRAGR_QA_NO_ROUND_EVENTS=1 FRAGR_QA_MANIFEST=res://qa/movement.json tools/qa_tour.sh .agents/qa/movement
```

It sends a sub-frame Space tap and walks ordinary inputs up/down the Arena Duel
stairs and off a ledge. The manifest records server feet and camera height;
`jump_peak.png` captures the actual hop. Timed round events are explicitly disabled
so a boss cannot kill the test player halfway through the route. This is a
movement check, not a combat playtest. Do not use `--publish` with this manifest.

M01's separate ten-state traversal tour uses `res://qa/m01.json` and a validated
local map file. Commands and scope are in [`server/maps/README.md`](../../server/maps/README.md).
It walks both stairs and the balcony underpass through live input, now clearing
the draft opening encounter along the way. `m01-discovery.json` checks ammunition
and reload; `m01-encounters.json` and `m01-maintenance.json` capture the two combat
approaches. The main tour now observes both enemy types firing before fighting
back and records their actual sprite frames with the server phases. Enemy artwork
remains under review and objectives are unbuilt. These
runs do not replace the release gallery or prove a finished mission.

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
