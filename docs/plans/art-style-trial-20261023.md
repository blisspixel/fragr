# Character art style trial

Status: **proposed**, 2026-10-23, finished 2026-10-24. Branch
`exp/art-style-trial`; local captures are evidence for Nick's decision. Nothing
here changes a shipped default, asset, setting or roster. Spend: $0 (local
renders only).

Nick asked to see a side-by-side trial before converting the roster. The target
is an "ultra modern boomer shooter" homage (Doom, Unreal, original
Counter-Strike, Battlefield 1942, Halo, Boltgun) where lore and fun lead. The
[vision](../VISION.md) asks for a 3D world with chunky pixel surfaces, the
[art bible](../ART_STORY_BIBLE.md) names Boltgun as the production reference,
and Nick chose live animated meshes for player bodies on 2026-10-08
([live character presenters](live-character-presenters-20261008.md)). Every
treatment is judged against the
[faction readability contract](../ART_STORY_BIBLE.md#faction-readability-contract)
(PR #455): Union black with red visors, armbands and optics; free bodies in
individual, player-chosen colour; the Inheritance in matte off-white, late game.

## Goal and non-goals

Goal: show a player body, a Union unit and a free agent in one real venue under
matched cameras and light, in each candidate treatment, with enough motion to
judge, and recommend one path with costs.

Non-goals: converting any unit, changing `skinned_character.gd`,
`enemy_view.gd`, shaders under `client/assets/` or settings defaults; judging
animation quality (every body uses the same procedural pose set, see Limits);
hardware performance claims.

## What was built

All under `client/art/style_trial/` (offline; `art/*` is excluded from every
export preset):

| File | Role |
|---|---|
| `art_style_trial.gd` | Builds Arena Duel from real `MapInfo`, places units, captures stills, clips and a small render cost probe, composes contact sheets and grayscale copies |
| `pixel_actor.gdshader` | Treatment A/C material: nearest low-resolution map, stepped (3 band) light, stepped edge light, cool fresnel band that fades with the texel, Union red marks burn bright, per-instance hit tint |
| `pixel_outline.gdshader` | Inverted hull in palette `outline_purple` (#3A2A48), one sprite texel wide in whole screen pixels, gone once a texel is smaller than a pixel |
| `trial_bake.gd` | Treatment B for the free human and free synthetic: the shipped directional bake (8 directions, 55 poses, 160 px cells, paired view normals) |
| `trial_livery.gd` | One player-chosen personal scheme for the free synthetic (worn mustard joints and trim over its sage body) in A, B and C |
| `trial_pose_source.gd` | Gives every unit the Clerk's authored pose set so all treatments start from identical poses |
| `inspect.gd` | Read-only listing of the trial sources' meshes, maps and clips |

Units: free human (the player body), Union Clerk, free agent (the selectable
synthetic body, not Latch). Venue: Arena Duel, map 1, the default free-for-all
map.

| Treatment | Meaning |
|---|---|
| S | Shipped today. Free bodies are live skins with their 1024 px maps sampled nearest; the Clerk is its shipped baked atlas (S and B are the same image for the Clerk) |
| A | Live skinned model, pixel material: 256 px nearest map reduced to a 24 colour palette per map, stepped light, normal map where the source has one, edge light, purple outline and fresnel band that fade at range, continuous facing and smooth motion |
| B | Baked 8 direction sprites with view normals under the shipped `union_sprite.gdshader`, extended to the human and synthetic |
| C | Hybrid: A's model and material, pose time held on a 12 fps clock, facing snapped to B's 8 directions, frame rendered at the existing 360 line integer pixel look |

Faction notes. The shipped synthetic is a sage body with clean bone joints and
trim; under the venue sun it reads pale at 10 and 25 m, close to the
Inheritance's pale read. A, B and C therefore wear one personal scheme
(`trial_livery.gd`): bone texels become worn mustard at their own value, so
wear and shading survive and the two free bodies do not share a uniform. S
keeps the shipped source so the divergence stays visible. Every hit cell
carries the shipped hit-flash modulate (`player_pawn.gd`, through
`SkinnedCharacter.tint()` on live skins).

## Captures

Root: `/home/pueo/Work/fragr/.agents/art-style-trial/` (ignored scratch).
Final sheets are in `sheets/` and motion in `motion/`, both from `run5/`, which
holds every cell, frame, clip frame and `receipt-all.json` (source hashes,
renderer, adapter). `run4/` is the earlier pass with a forced one pixel outline,
kept for the speckle comparison.

- Cameras: eye 1.6 m, 75 degree FOV, 1280x720, at 3 m, 10 m and 25 m. Cells are
  nearest crops, 10 m at 2x and 25 m at 4x.
- Light set: south gantry face, sun behind camera. Shade set: north gantry cast
  shadow, sun behind the unit.
- Poses per cell: idle, run, fire, hit (mid flinch with the hit flash), death.
- Motion: run (4 m/s while turning) and combat (raise, two shots, hit,
  collapse), 72 frames at 30 fps per unit and treatment; side-by-side S|A|B|C
  clips as MP4 and GIF.

| Sheet | Shows |
|---|---|
| `sheets/sheet_S.png`, `sheet_A.png`, `sheet_B.png`, `sheet_C.png` | Contact sheet per treatment: 3 units x light/shade x 3 distances x 5 poses |
| `sheets/compare_light.png`, `compare_shade.png` | Idle, fire, death with S, A, B, C side by side per row |
| `sheets/compare_light_gray.png`, `compare_shade_gray.png` | The same in Rec. 709 luma, for the contract's grayscale read |
| `sheets/context_groups.png` | All three units together in the venue, full frames |
| `sheets/strips_<unit>.png` | Motion strips per treatment |
| `motion/<unit>_<run or combat>.mp4` (and `.gif`) | S, A, B, C playing together |

Reproduce (Godot 4.7.2, windowed, Dummy audio):

```bash
godot --path client --rendering-driver opengl3 --windowed --audio-driver Dummy \
  --script res://art/style_trial/trial_bake.gd -- <abs bake dir> human synthetic
godot --path client --windowed --audio-driver Dummy \
  --script res://art/style_trial/art_style_trial.gd -- \
  <abs out dir> <abs bake dir> <host:port of a fragr-server | abs map_info.json>
```

A second bake on 2026-10-24 reproduced all four atlases byte for byte
(`bake5-verify/`). The capture run printed `art_style_trial: PASS (all)` with
no errors or warnings.

## Research (2026-10-23)

| Game | Character technique | Source |
|---|---|---|
| Boltgun | 3D models rendered by virtual cameras from eight directions per animation frame, reassembled as flipbooks on camera-facing sprites; Auroch rewrote the sprite renderer for counts | [PlayStation Blog, 2023-04-11](https://blog.playstation.com/?p=377958), [Xbox Wire, 2024-06-18](https://news.xbox.com/en-us/?p=202509) |
| Boltgun 2 | Same eight direction capture, sheets packed with normal, ambient occlusion and emission data on billboards | [Creative Bloq](https://creativebloq.com/3d/video-game-design/warhammer-40-000-boltgun-2s-lead-artist-reveals-how-they-made-pixel-art-feel-authentically-retro) |
| Prodeus | 2D enemies lit by the 3D scene; the Kickstarter promised a sprite or 3D model switch; optional low resolution output | [bit-tech preview](https://bit-tech.net/reviews/gaming/pc/prodeus-preview/1/), [DSOGaming](https://www.dsogaming.com/news/kickstarter-campaing-launched-for-prodeus-old-school-first-person-retro-shooter-using-modern-rendering-techniques/) |
| Turbo Overkill | Low poly 3D models wrapped in pixel art textures under modern neon light | [Sportskeeda review](https://sportskeeda.com/esports/turbo-overkill-review-hail-leg-chainsaw-baby) |
| Ultrakill | Low poly 3D, described by its developer as PS1 style | [Steam discussion](https://steamcommunity.com/app/1229490/discussions/0/3002177675804624601) |
| Dusk | Low poly 3D models, low resolution limited palette textures | [Wikipedia](https://en.wikipedia.org/wiki/Dusk_(video_game)) |
| Cultic | 2D sprites and voxels in a 3D world with heavy colour reduction | [Xbox store](https://www.xbox.com/games/store/cultic/9NNQ1JQ1FSZL) |

Finding: the two games the brief names for the pixel look, Boltgun and
Prodeus, both ship directional sprites lit in 3D, which is Treatment B. Live
low poly 3D with pixel textures (Treatment A) is the Turbo Overkill, Ultrakill
and Dusk family. Sources are interviews, previews and reviews, not engine
documentation.

## Observations

- **S is two games.** Free bodies are smooth, finely textured live meshes with
  no outline; the Clerk is an outlined, stepped sprite. Side by side at 3 m they
  do not share a material language.
- **A** keeps faces and hands readable at 3 m and keeps a true foreshortened
  body in death. Stepped light and the outline pull the free bodies toward the
  Union sprites. With the outline and fresnel band fading at range, the 25 m
  figures are clean warm masses; run4's purple speckle is gone. On the Clerk,
  A is weaker: the reduced map under warm venue light turns black cloth into a
  brown mottle at 10 m and the red visor shrinks to a pixel or two at 25 m, so
  it misses the contract's dark mass with steady red points.
- **B** reads closest to Boltgun and gives the Clerk the cleanest Union read at
  every range: a black mass with red points, in light and shade. At 3 m a
  160 px cell (about 1.9 cm per texel) blurs faces, and the unlit bake under
  the sprite shader is darker than the live bodies: in grayscale the B free
  bodies sit closer to the Clerk's value than A or S do, which costs the free
  side some value contrast. Death on a billboard collapses to a thin blob seen at eye height.
  Facing pops between 8 cells during turns.
- **C** is the most old school in motion (12 fps steps and snapped facings), but
  the 360 line frame turns faces to mush by 10 m and dissolves units into a few
  blocks at 25 m.
- **Grayscale.** In A and S the free bodies stay mid value against the dark
  Clerk at all three distances; in B only silhouette separates them.
- **Hit.** The shipped hit flash is a strong red wash on every body. It reads
  at every range, but it is the Union's tell colour on a free body (open
  question 3).
- In shade every treatment stays readable at 10 m; B's rim gives the cleanest
  silhouette, A's edge light the next cleanest.

## Render cost probe

Sixteen walking actors in the light set, 1280x720, Forward+, AMD Radeon 780M
(RADV), 120 samples after warm up, `run5/receipt-all.json`. One machine; this
is relative evidence, not a hardware claim. The earlier run4 probe under heavy
host load gave the same ordering (A 4.40, B 3.07, C 2.89 ms GPU median).

| Case | GPU ms median | GPU ms p90 | CPU ms median |
|---|---|---|---|
| Venue only, full frame | 1.54 | 1.79 | 0.13 |
| Venue only, 360 line frame | 0.62 | 0.63 | 0.12 |
| A, 16 live skins | 2.85 | 2.97 | 0.30 |
| B, 16 sprites | 1.71 | 1.75 | 0.22 |
| C, 16 live skins, 360 line frame | 1.79 | 1.82 | 0.29 |

## Costs

All options are $0 in services. Effort figures are estimates for planning,
not measurements.

| Path | Work | Runtime cost | Memory |
|---|---|---|---|
| A for live skins (human, synthetic, Tern, Edda; Splice's rigid presenter separately) | One material swap inside `skinned_character.gd` with the texel fade, hit tint through the material, texture reduction offline or at load mapped to `docs/palette.json` ramps; harness, tour, both renderers. About one focused PR | About +0.07 ms GPU per skin over B in the probe; outline is a second draw | Small: 256 px maps instead of 1024 px |
| A for the Union roster | Each Union source is a pose builder that instances a model per pose; live use needs a persistent skeleton, live attack tells, plates, red glow parity and a black-cloth palette rule for nine units. Several PRs per unit family | As above, for every enemy in a room | Removes atlases |
| B for player bodies | Bake is cheap (two units in 4.5 to 15.5 s); but live skins carry continuous aim pitch, crouch, floor support and seated poses that sprites lose, and Nick chose live meshes on 2026-10-08 | Lowest per actor | Each 2880x4000 lossless atlas is about 46 MB of VRAM, 92 MB with normals |
| C everywhere | A's work plus a 12 fps pose clock and facing snap; frame resolution is a global setting, so faces cannot be protected | Cheapest frame, but blurs everything | As A |
| Personal colour for free bodies | A body colour picker validated on the composed body as the contract specifies, applied as a value-preserving repaint like `trial_livery.gd`; one PR after A lands | None at runtime beyond one repainted map per body | One 256 px map per scheme |

## Recommendation

1. Adopt **A's material for every live skin** (player bodies and named cast),
   with the outline and fresnel band fading out once a texel is smaller than a
   pixel, as captured here. This keeps Nick's live mesh choice, keeps faces and
   aim readable for the multiplayer homage (Counter-Strike, Battlefield 1942
   and Halo depend on reading where a player is pointed), keeps free bodies
   mid value against Union black, and closes most of the gap to the Union
   sprites.
2. **Keep B for Union enemies.** It is the technique Boltgun actually uses, it
   is already built, it is the cheapest at room counts, and it gives the best
   contract read (black mass, red points) of any treatment. Raise its close
   range by testing a 192 px cell for officer ranks only, and give death a
   ground plane frame instead of a billboard.
3. **Do not adopt C's 360 line frame for characters.** Keep the 12 fps pose
   clock as a later optional "old school motion" setting to test in play, not
   as the default.
4. Give free bodies **personal colour** once A lands: the composed-body
   colour picker from the contract, starting from a repaint like
   `trial_livery.gd`, so no shipped free body keeps a pale bone dominant read.

Success for step 1 would be: at 3, 10 and 25 m in light and shade, a live body
and a Union sprite read as one game in `compare_light.png` style captures, with
no purple speckle at 25 m, a mid value free body against a dark Union body in
the grayscale copies, and no regression in the standard tour.

## Limits

- Every unit uses the Clerk's procedural pose set (hands near the hips at idle,
  a small pistol, the Clerk's walk). The trial compares rendering, not
  animation; the shipped free bodies have their own clips.
- Treatment A's palette is a per map k-means reduction, not a hand authored
  ramp; a production version should map to `docs/palette.json` ramps.
- The free synthetic's scheme is one example of a player choice, not a picker.
  Colour-vision review was not run; the trial has no colour-vision filter.
- One venue, one machine, no played sequence. Arena Duel alone cannot prove
  the look across campaign interiors or night venues, and no Inheritance
  machine exists yet to check the late game read.

## Open questions for Nick

1. Is the split (A for live skins, B for Union enemies) acceptable, or should
   one treatment cover everything even at higher cost?
2. Should the outline stay `outline_purple` on free bodies, or should Union and
   free sides differ (for example red tells only on Union)?
3. Should the hit flash stay red on free bodies, given red is the Union tell
   colour, or move to a warm white flash?
4. Is a 12 fps "old school motion" toggle worth a playtest?
