# fragr art and story direction

Current direction, 2026-09-19. Product intent lives in [`VISION.md`](VISION.md);
world canon and frozen voice vocabulary live in [`lore/`](lore/README.md).
This replaces the early arena-only notes. Campaign depth and retro menus are
explicit parts of the current target.

## North star

An original, fast, readable 3D FPS with chunky pixel surfaces, heavy weapon
silhouettes, theatrical combat feedback, and industrial grit. The references are
modern boomer shooters and the pace, spaces, and social fun of early arena/LAN
shooters. Real 3D movement and camera, pixel craft on the surfaces. No copied
characters, weapons, logos, or map layouts.

Boltgun is the production-quality reference: detailed pixel fighters and guns,
substantial pose animation, sculpted 3D spaces, strong directional lighting, and
forceful readable effects. Sparse geometry, static character cards, and enlarged
placeholder flashes do not meet this bar. Judge animation, weapon weight, impact,
and environment cohesion in a played sequence, not only a selected still.

The setting is serious beneath the absurdity: free humans and conscious embodied
agents, the authoritarian Union/Chancellery and its enslaved agents, and the Quiet's
ecological recovery through mass killing. The same catastrophe looks like doomsday
or a flood to different survivors. Show ruined institutions, propaganda, machinery,
regrowth, and contradictory evidence through places and encounters. Keep the actual
scrap fast and funny. Lore depth belongs in the world; do not stop combat for essays.

## Visual grammar

| Element | Direction |
|---|---|
| World | Dark steel, worn enamel, rust, concrete, cables, vents, practical lights, stenciled identifiers, and readable landmarks. Distinguish each arena's purpose. |
| Surface detail | Deliberate pixel clusters and consistent texel scale. Broad readable material shapes before fine wear. Avoid uniform grids on every surface. |
| Fighters | Distinct silhouette, facing, faction, weapon, and damage state. Cyanex and Kragge remain seed identities. Flesh or metal does not establish moral status. |
| Weapons | Flechette, rail, and scatter must read by silhouette and feedback alone. Separate inventory icons from first-person art. Preserve muzzle registration across frames. |
| Effects | Short, forceful flashes, impacts, debris, and pain/death response. Color and sound communicate the event. Avoid glow that hides targets. |
| Menus/settings | Chunky pixel type, bone titles, metal framing, physical controls, and strong selection states. The entire front end belongs to the retro FPS. |
| Gameplay HUD | Health, armor, weapon, aim, and urgent feedback first. Keep broadcast decoration out of the fight. |
| Spectating | Fighter perspective is first class. Broadcast identity and optional richer match information can frame watching. |
| Story surfaces | Original slogans, unreliable radio, environmental contradictions, and occasional 67 jokes. No real broadcaster names or tribute skins. |

Free communities repair and repurpose. Union spaces impose repeated forms,
inspection lanes, serial numbers, and controlled institutional color. The Quiet
leaves unsettling order and regrowth among evidence of human and agent loss.
These are visual tendencies, not a replacement for the detailed faction canon.

## Palette and type

[`palette.json`](palette.json) owns the exact base swatches. Lighting can shade
them; keep accents purposeful and silhouettes distinct from their background.

| Role | Base color |
|---|---|
| Ink / void | `#0A0A0C` |
| Bone | `#E8E2D6` |
| Outline purple | `#3A2A48` |
| Dark steel / gunmetal | `#3A3836`, `#5A554F` |
| Rust / dried blood | `#7A3A22`, `#6E1218` |
| Ember | `#C45A20` |
| Muted signal cyan / magenta | `#4A8A92`, `#8A3A58` |
| Broadcast red | `#8B1E1E` |

Bone-white outlined titles and compact pixel-readable body type. Current menu
fonts and their required licenses live in `client/assets/fonts/`. No neon floods,
photoreal military treatment, smooth mobile UI, or tiny noisy detail masquerading
as pixel art. Accent colors identify teams, pickups, heat, or landmarks.

## Locked references

- `docs/fragr-logo-GOLD.png` and `docs/fragr-logo.png`: preferred bone wordmark,
  dark purple outline, restrained broadcast red, matte void triangle. Preserve
  the original identity and the meatbags/agents premise.
- `docs/fragr-keyart-v4-no-codes.png`: palette and atmosphere reference. Do not
  stamp internal layout codes such as HUB/CHOKE/PIT/HIGH onto marketing art.
- `docs/weapon-plates/`: shape references. Large source plates are not proof that
  an asset reads in the game. Inspect the actual imported frame at play resolution.
- Callsigns and terms already spoken in committed audio are frozen in
  [`lore/voice.md`](lore/voice.md). Check that file before renaming them.

The approved wordmark has the weight and attitude of a rock-racing title:
angular bone lettering, worn faces, deep purple extrusion, and restrained red.
Preserve its original shapes and matte finish. The compact identity is meatbags
(humans), conscious agents with agency, and a looming AGI singularity. Humans
and agents share the foreground; the presence above them suggests the larger
change neither controls. The broadcast sign and waveform are supporting details.
The [arrival premise](lore/belief.md#the-arrival) gives that looming presence its
religious weight without turning the mark into a literal picture of a god.

## Production and evidence

Use existing assets and authored in-repo materials first. Developer generation
belongs to `tools/spritegen` and `tools/audiogen`, with approved credits, explicit
caps, and provenance. Do not put provider calls into player runtime or CI.
Fix asset sources or preparation commands and regenerate derived frames.

Canonical imported assets live under `client/assets/`. Pixel textures use nearest
filtering and the established import settings. Record source/spec, preparation,
format, and intended use with each generated asset. A coherent animation set needs
consistent scale, pose registration, palette, and silhouette across every frame.

Current implementation has three prepared idle viewmodels and six server-owned
map layouts; finished enemy animation, world dressing, and campaign environments
remain work in progress. Current captures are `docs/screenshots/tour_*.png`, made
with `tools/qa_tour.sh --publish`. Inspect the world, close combat, menus, and brief
effects in both supported rendering paths before accepting a presentation change.
Nonblank images, pixel counts, and green headless tests do not establish good art.
