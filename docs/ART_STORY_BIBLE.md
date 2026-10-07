# fragr art and story direction

Current direction, 2026-10-03. Product intent lives in [`VISION.md`](VISION.md);
world canon and frozen voice vocabulary live in [`lore/`](lore/README.md).
This replaces the early arena-only notes. Campaign depth and retro menus are
explicit parts of the current target.

The [design continuity guides](design/README.md) apply this direction to Earth,
the Moon, Mars, ships, characters, voices and scenes. Their world sections map
to the [level plans](campaign/README.md); they share this bible and the lore,
rather than maintaining separate palettes or competing canon.

## North star

An original, fast, readable 3D FPS with chunky pixel surfaces, heavy weapon
silhouettes, theatrical combat feedback, and industrial grit. The references are
modern boomer shooters and the pace, spaces, and social fun of early arena/LAN
shooters. Real 3D movement and camera, pixel craft on the surfaces. No copied
characters, weapons, logos, or map layouts.

Retro is the direction, never a quality ceiling. Every asset, model and map is
judged against the modern boomer shooters that look excellent (Boltgun,
Prodeus, Dusk, Ultrakill, Cultic), at game scale, in motion and under light.
Plain boxes, muddy sprites and barren rooms are defects, not style. See
[art excellence](plans/art-excellence.md).

Characters are deliberately stylized, including human faces. Use angular
sculpted planes, expressive simplified features, broad painted values and
coherent pixel clusters across people, robots, weapons and rooms. Photographic
skin, pores, fabric weave and dense realistic material noise do not fit this
direction. Shrinking a photographic person is not a completed pixel character.

The campaign's loose reference is around 2070, confirmed on 2026-10-03.
Established Moon and Mars bases coexist with recognizable industrial hardware,
CRT-like displays, physical controls, civilian firearms and personally repaired
electronics. A few advanced systems should have clear purposes and mechanical
weight. Keep the retro-futuristic charm in materials, interfaces and lived use.

Boltgun is the production-quality reference: detailed pixel fighters and guns,
substantial pose animation, sculpted 3D spaces, strong directional lighting, and
forceful readable effects. Sparse geometry, static character cards, and enlarged
placeholder flashes do not meet this bar. Judge animation, weapon weight, impact,
and environment cohesion in a played sequence, not only a selected still.

### Influences and the original house style

| Influence | What guides fragr |
|---|---|
| Doom and Doom II | Immediately legible combat rooms, deliberate landmarks, useful secrets, animated surfaces and forceful weapon feedback |
| Quake and early arena/LAN shooters | Real 3D routes, height changes, fast movement, readable weapon roles and the pleasure of watching or joining the same fight |
| Boltgun and modern retro FPS craft | Detailed directional pixel actors, substantial poses, weight, directional light and cohesive sculpted spaces at playing distance |

These are craft influences. fragr's people, institutions, equipment, places,
marks, dialogue and layouts come from its own canon. The game is a real 3D
shooter with deliberately pixelated surfaces and presentation. Low resolution
does not excuse empty rooms, weak silhouettes, flat lighting or incoherent art.

## Environment detail and water

A place should explain who uses it, what they do there and what just happened.
Nick clarified on October 4 that large spaces are welcome when their purpose
and construction are believable. A lunar dome or ship hangar can contain a
large air volume; show its pressure boundary, structural supports and useful
service routes. Outdoor yards, streets and natural terrain remain part of the
variety. Plausibility does not mean turning every map into tight corridors.
Judge what the space supports and how people use it, not openness alone.
Start with an identifiable activity: a clinic receiving patients, a repair
market sharing tools, a freight yard sorting people, an institution enforcing a
queue. Put detail around that activity. Repeated generic crates and vents cannot
establish every district. Keep possessions specific, repairs plausible and large
shapes useful to navigation. Read [MAP-DESIGN.md](MAP-DESIGN.md) alongside this
guide before changing encounter space.

The [world texture expansion](plans/world-texture-expansion.md) applies these
rules through separate Earth, Moon and future Mars material families. Albedo
tiles describe a material's use and maintenance. Keep lighting in the renderer,
match opposite edges, and inspect repetition from player height. A quiet clinic
wall, traction deck and dry regolith must read as different things. Palette
reduction and a larger generation setting alone do not establish quality.

Use three viewing scales consistently:

- At a room's entrance: a clear destination, one useful landmark, readable
  cover and distinct floor/wall/ceiling forms.
- At fighting distance: doors, windows, repairs, service runs, warm practical
  light and purposeful surface variation that leaves enemies and attack tells
  clear.
- Up close: coherent pixel wear, labels, fasteners, small litter and local
  possessions. Their density supports the room rather than covering every face.

Low Water is a lived-in free community before the wipe: worn plaster, repaired
stalls, cloth awnings, personal windows, shared meals, charging cables, patched
utility work and rooftop water tanks. Late-afternoon light and a residential
skyline distinguish it from a prison or generic industrial arena. Its residents
include humans and embodied agents; possessions and repairs show individuality,
not a universal rebel uniform. The clinic can be calm while the street is
dangerous. Use [the M04 brief](campaign/l04-notice-to-vacate.md) and
[gazetteer](lore/gazetteer.md) for place-specific continuity.

Water belongs where drainage, infrastructure or geography explains it. Use
animated, stepped pixel ripples, a restrained blue-green/value ramp, irregular
wet edges and readable banks or grates. The effect should read under actual
world light and the Compatibility renderer. Environmental water stays distinct
from attack flashes, pickups and waypoint colors. Avoid refraction that hides
shots or animated noise that competes with a Notary's tell.

Shallow cosmetic runoff sits flush on existing ground and never creates a
swimming or falling promise. A pool, canal, deep flooded room, damaging liquid,
current or swimming route needs authored geometry and an explicit server rule
before presentation implies that behavior. The initial
[water foundation](plans/environment-water-foundation.md) covers M04 puddles;
other locations remain authored work. Pre-wipe runoff does not imply the clean
ecological recovery that appears years after the catastrophe.

Wall wear, drainage and litter can be nonblocking presentation. A stall, tank,
machine or furniture body that appears to stop a pawn or shot belongs in
authoritative solids. Cosmetic dressing cannot silently alter routes, supply
reachability, cover, enemy sightlines or combat.

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
| Fighters | Distinct silhouette, facing, faction, weapon, and damage state. Participants wear the body they chose, a human or a free agent in a synthetic body ([plan](plans/player-body-selection.md)); Cyanex and Kragge remain only for fighters an older server sends without one. Flesh or metal does not establish moral status. |
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

Nick's 2026-10-03 clarification applies to asset production: the Union is an
expanding, plausible fascist institution with standardized equipment, compliance
controls and German official-language presentation. Its violence appears in
confiscation, forced labor, recalls and identity erasure, carried out by people
and systems that can look ordinary and competent. Use original institutional
marks and designs; the [Chancellery rule](lore/the-chancellery.md#felt-never-named)
owns the historical echo and language treatment.

Black field uniforms, dark steel armor, peaked service caps and clear deep-red
bands or seals identify the Union at fighting distance. Keep the body palette
black and red, with plates only slightly lighter and deliberate red attack
tells. Pale armor must not dominate these soldiers. Use severe institutional
shapes and stylized faces consistently across their human and machine ranks.
This is the outfit and issued-equipment signature, not a universal wall palette.
Buildings retain their place-specific plaster, enamel, timber, concrete, steel
and maintenance history. Civilian Low Water rooms keep warm personal variation;
institutional interiors use controlled accents without painting every wall red.

Free humans and agents have varied civilian clothes, chassis, equipment and
personal repairs. Hackers, workshop people and neighbors would prefer a quiet
free life; their chosen resistance does not turn everyone into an armored
soldier. Conscious agents' personhood is certain. Individual motives, consent,
mistakes and competing loyalties provide moral complexity without making
enslavement or deletion an equally valid position. The Inheritance's emerging
reach belongs in recurring infrastructure anomalies and unreliable radio,
not an early explanation of the wipe's timing.

Latch is a free embodied person, roughly six feet (about 1.8 metres) tall, with
scrappy repairs and personally chosen parts. Their head is a CRT-like framed
screen, taller than wide, showing soft friendly pixel faces, with one thin
antenna on the anatomical left ear. Keep that head,
expressions and individually repaired silhouette consistent across worlds and
scenes. A fighting role does not make Latch
a war bot. Design the individual before the weapon: recognizable gestures,
preferences, relationships and a body maintained through its own choices.
The body is lean, with modest shoulders and articulated civilian proportions.
Avoid a muscular superhero silhouette or heavy built-in combat armor.
The main human is a chill stoner-gamer dude who wants music, scrap, friends and
a free life. Nick clarified on October 4 that the freedom-loving influence is
light, not literal cowboy costuming. The default reference is hatless civilian
workwear: a worn utility jacket, casual layers, dark work pants, practical
footwear and an easy visible face and posture. Free humans include mechanics,
hackers, medics and other ordinary people with varied clothes and possessions.
Western accessories may be an occasional personal choice, never the default
body or a faction uniform. A scavenged long rifle is gear when needed,
not a personality. Avoid theatrical costumes or expensive tactical armor. Both have
limited means; maintained possessions and personal repairs show dignity and
choice rather than wealth. Nick's October 1
[duo reference](../client/art/characters/references/free-duo-reference.png)
sets this shared read; the character brief refines the screen proportions,
antenna side, optional clothes and temperament. Current bodies remain
provisional implementations.
Latch shares the almost stoner-cool ease in metal: dry, practical, likable and
capable of affection, disagreement and a familiar fist bump. Both are people
you would want to smoke a bowl and chill with. They choose to stand tall when
the call to defend freedom comes. Recall, custody and clanker slavery leave
them no peaceful way to keep their lives and friends safe. They are freedom
fighters by necessity, soft people under hard authority; courage grows from
warmth and conviction rather than replacing them with a battle persona.
The human direction carries a freedom-loving American spirit through voluntary
association, speech, self-defense and practical independence. In the campaign,
people identify as free humans and agents, or by their allegiance to the Union;
old national citizenship is not a faction, uniform or test of personhood.
The Union deliberately suppresses both human and machine autonomy through
licensing, forced dependence and ownership. Its issued bodies and controlled
spaces make that coercion visible. The [character guide](design/characters.md)
and [people and agents](lore/people-and-agents.md) own the detailed brief.

The free communities' [rattlesnake banner](../client/assets/factions/free_coalition/README.md)
is available as inspected flat artwork. Organic scales, repaired mechanical plates
and broken restraints express shared freedom for humans and agents. It is one
resistance emblem, not a uniform every free community must adopt. No shipped map
placement is claimed. Its warm worn field is an intentional banner accent.

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
| Institutional green (Union interiors) | `#4E5844` |
| Union black / steel / plate | `#1E1E22`, `#2C2D32`, `#56575E` |
| Union red / red optics | `#8C1A1E`, `#E23430` |
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
| Free humans and free agents | Bone and white, warm leather, rust and ember, purple outline, small personally chosen cyan or magenta accents. They read as the people the player is fighting for | Repaired equipment, exposed fasteners, asymmetry, distinct gestures. Humans and agents share practical clothing and tools; no universal rebel uniform |
| Union humans and bots | Black cloth, dark steel and plates one step lighter, with restrained red: visors and optics, armbands and seals. Red optics are also every Union attack tell light | Issued rectangular plates, covered mechanisms, repeated numbered insignia, disciplined ranks. Menace comes from uniformity and order, never spikes, skulls or cartoon villainy. Plates and red accents keep bodies readable in dark rooms. Human officers and controlled bots remain distinguishable by shape and movement |
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

Current implementation includes six server-owned arcade layouts and four local
campaign prototypes, with directional combat actors and original Jammer/Notary
poses. Finished weapon animation, world dressing and campaign environments
remain work in progress. Current captures are `docs/screenshots/tour_*.png`, made
with `tools/qa_tour.sh --publish`. Inspect the world, close combat, menus, and brief
effects in both supported rendering paths before accepting a presentation change.
Nonblank images, pixel counts, and green headless tests do not establish good art.

For every asset batch, record the intended room or scene, lore reference,
palette, target size and texel density before generation. Review candidates
beside existing assets, prepare keepers through the existing tools, then inspect
them in the actual lit scene and in motion. Keep caption and recorded narration
wording together. Advance a bounded batch only after its preceding receipt is
reconciled; a credit balance is an allowance, not an instruction to spend it all.
