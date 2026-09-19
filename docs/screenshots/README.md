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

The full tour also checks rail/scatter selection, return to spectating, the
multiplayer page, all three settings tabs, and settings inside the live match
overlay. Captures use an isolated settings file. The local manifest records actual
map, round, role, weapon, dimensions, and flash visibility. Intermediates live in
`.agents/qa/`. Set `FRAGR_RENDER_DRIVER=vulkan` to check that rendering path;
OpenGL compatibility is the tour default. This is renderer evidence on the
recorded host, not a GPU vendor certification or a load benchmark.

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
