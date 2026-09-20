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
agents, the authoritarian Union/Chancellery and its bots, and the Inheritance's
ecological recovery through mass killing. The same catastrophe looks like doomsday
or a flood to different survivors. Show ruined institutions, propaganda, machinery,
regrowth, and contradictory evidence through places and encounters. Keep the actual
scrap fast and funny. Story belongs in lived spaces, characters, localized framing, and brief scenes;
do not stop combat for essays. The wipe's onset is sudden despite gradual
recognition of the intelligence. Play continues into the aftermath.

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
inspection lanes, serial numbers, and controlled institutional color. The Inheritance
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
| Institutional green | `#4E5844` |
| Vegetation shadow / leaf | `#3A4C2E`, `#74884E` |

Bone-white outlined titles and compact pixel-readable body type. Current menu
fonts and their required licenses live in `client/assets/fonts/`. No neon floods,
photoreal military treatment, smooth mobile UI, or tiny noisy detail masquerading
as pixel art. Accent colors identify teams, pickups, heat, or landmarks.

The green swatches are an authoring extension for campaign institutions and
ecological recovery, not a claim that existing assets have been recolored.
`on_air` remains a compatibility palette key for the dark red; its name does not
require radio branding or a logo plaque. Avoid inventing new swatches per prompt.

## Factions, places and continuity

These are proposed production constraints for the campaign, not completed asset
sets. Location supplies material and light; faction supplies manufacture and
marking. Neither replaces the other. A Union lunar depot must read as both.

| Group | Palette roles | Silhouette, material and motion |
|---|---|---|
| Free communities | Gunmetal, rust and worn bone; small personally chosen cyan, ember or magenta accents | Repaired equipment, exposed fasteners, asymmetry, distinct gestures. Humans and agents share practical clothing and tools; no universal rebel uniform |
| Union humans and bots | Repeated bone panels, institutional green, dark steel and limited dark red seals | Issued rectangular plates, covered mechanisms, repeated numbered insignia, disciplined ranks. Human officers and controlled bots remain distinguishable by shape and movement |
| Inheritance restoration machines | Matte bone over ink joints; minimal muted cyan working indicators | Continuous unfamiliar surfaces, few seams, no serials or faces, deliberate coordinated motion. Never a neon faction |
| Absorbed Union bots | Preserve their existing Union paint, wear and chassis at onset | Marks do not magically vanish. Shared timing, changed targeting and loss of response to human command reveal absorption. Free agents do not acquire this motion |

| Environment | Dominant materials and color | Light, landmarks and lived detail |
|---|---|---|
| Earth civilian interiors | Worn plaster/bone, steel, wood-like warm gunmetal and rust; personal accent colors | Practical warm lamps, low service passages, real ceilings, possessions and repair histories |
| Earth Union institutions | Bone enamel, institutional green, dark steel, restrained red seals | Repeated service lighting, counters, queue lanes, numbered thresholds and visible control infrastructure |
| Earth exteriors | Concrete, weathered steel, soil and muted vegetation | Overcast daylight or authored sun; buildings, drainage and trees enclose views. Each district has a recognizable route landmark |
| Moon | Bone/gray mineral dust, dark basalt, weathered pressure shells | Hard exposed light and deep shade outside; readable fill and warm utility lighting inside. Crater rims, docks, airlocks, dust at thresholds; no generic blue space tint |
| Mars | Rust terrain, worn pale shielding, dark industrial frames | Dust-filtered amber exterior light balanced by neutral interiors; pressure doors, wind protection, hab modules and contained agriculture. People and gunfire must separate from the red ground |
| Ship and deep space | Gunmetal ribs, bone pressure doors, reused mission cargo, restrained cyan navigation equipment | Distinct deck lighting and machinery rhythm; black space seen through bounded apertures. Habitable rooms, not endless glowing corridors |
| Immediate wipe | Preserve the pre-wipe palette and landmarks | Local failures, interrupted light, infrastructure movement and imported machines. No instant vegetation, global green wash or invented new planet |
| Years-later Earth | The same recognizable structures with moss and leaf accents, clean water and weathering | Natural light reaches newly opened spaces. Visible regrowth coexists with memorials, absences and surviving communities |

Exterior Earth lighting changes by place and time; Mars is not every orange room,
and the Moon is not every gray corridor. Use framing, pressure equipment, geology,
sky and story context together. Offworld settlement silhouettes share a plausible
industrial ancestry but have local adaptations. Do not add different gravity to
a scene without an authored, implemented movement rule.

Team colors, aim feedback, damage and pickup cues keep their gameplay meanings.
Use outline, silhouette, insignia and behavior as well as color for allegiance;
a cyan panel is not a promise of safety. Check fighting readability under every
environment's actual light, including color-vision and grayscale review.

### Character reference contract

[Cast](lore/cast.md#visual-continuity) owns proposed recurring-character anchors.
Before production, establish a shared reference sheet for each: stable actor ID,
body/proportions, front/side/back silhouette, palette keys, outfit and equipment,
scale beside a doorway and weapon, and signature poses. Record deliberate damage,
repair and outfit changes by mission; transport alone does not redesign a person.

Use those same references for sprites, portraits, chapter panels, voice casting
and movies. A free agent and a Union bot can share a chassis family; restrictions,
markings, behavior and the person's history carry the difference. Custom player
body, callsign and cosmetics must survive framing, inventory views and cutscenes.
Prefer first-person or body-neutral shots where a fixed movie cannot represent
the player's choices accurately.

An asset is accepted in a contact sheet beside its faction, environment and
character references, then in motion beside existing game assets. Check pixel
cluster size, texture density, proportions, pose registration and lighting.
Downscaling a drifting photoreal clip does not establish coherent pixel art.

## Locked references

- `docs/fragr-logo-GOLD.png` and `docs/fragr-logo.png`: preferred bone wordmark,
  dark purple outline, restrained broadcast red, matte void triangle. Preserve
  the original identity and the meatbags/agents premise.
- `docs/fragr-logo-refined.png`: 2026-09-19 refinement preserving that lettering
  and the emerging-intelligence signal, removing the ON AIR plaque, and showing
  free human/agent partners opposite uniformed Union forces. Original reference
  stays intact. The signal belongs to the growing intelligence, not radio branding.
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
change neither controls. The refined mark removes the broadcast plaque and keeps
the waveform as a restrained suggestion of the growing intelligence.
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
