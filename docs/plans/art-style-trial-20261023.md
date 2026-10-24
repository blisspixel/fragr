# Character art style trial

Status: **proposed**, 2026-10-23. Experiment branch `exp/art-style-trial`; local
captures are evidence for Nick's decision. Nothing here changes a shipped
default, asset, setting or roster. Spend: $0 (local renders only).

Nick asked to see a side-by-side trial before converting the roster. The target
is an "ultra modern boomer shooter" homage (Doom, Unreal, original
Counter-Strike, Battlefield 1942, Halo, Boltgun) where lore and fun lead. The
[art bible](../ART_STORY_BIBLE.md) already names Boltgun as the production
reference and Nick chose live animated meshes for player bodies on 2026-10-08
([live character presenters](live-character-presenters-20261008.md)).

## Goal and non-goals

Goal: show three units in one real venue under matched cameras and light, in
each candidate treatment, with enough motion to judge, and recommend one path
with costs.

Non-goals: converting any unit, changing `skinned_character.gd`,
`enemy_view.gd`, shaders under `client/assets/` or settings defaults; judging
animation quality (every body uses the same procedural pose set, see Limits);
hardware performance claims.

## What was built

All under `client/art/style_trial/` (offline, excluded from runtime paths):

| File | Role |
|---|---|
| `art_style_trial.gd` | Builds Arena Duel from real `MapInfo`, places units, captures stills, clips and a small render cost probe, composes contact sheets |
| `pixel_actor.gdshader` | Treatment A/C material: nearest low-resolution map, stepped (3 band) light, stepped edge light, cool fresnel band, Union red marks burn bright |
| `pixel_outline.gdshader` | Inverted hull in palette `outline_purple` (#3A2A48), whole screen pixels, about one sprite texel wide |
| `trial_bake.gd` | Treatment B for the free human and civilian synthetic: the shipped directional bake (8 directions, 55 poses, 160 px cells, paired view normals) |
| `trial_pose_source.gd` | Gives every unit the Clerk's authored pose set so all treatments start from identical poses |
| `inspect.gd` | Read-only listing of the trial sources' meshes, maps and clips |

Units: free human (player body), Union Clerk, civilian synthetic (free agent).
Venue: Arena Duel, map 1, the default free-for-all map (no `feat/larak-lot`
branch exists on origin; checked 2026-10-23).

| Treatment | Meaning |
|---|---|
| S | Shipped today. Free bodies are live skins with their 1024 px maps sampled nearest; the Clerk is its shipped baked atlas (S and B are the same image for the Clerk) |
| A | Live skinned model, pixel material: 256 px nearest map reduced to a 24 colour palette per map, stepped light, normal map where the source has one (human, Clerk; the synthetic has none), rim and fresnel, purple outline, continuous facing and smooth motion |
| B | Baked 8 direction sprites with view normals under the shipped `union_sprite.gdshader`, extended to the human and synthetic |
| C | Hybrid: A's model and material, pose time held on a 12 fps clock, facing snapped to B's 8 directions, frame rendered at the existing 360 line integer pixel look |

## Captures

Root: `/home/pueo/Work/fragr/.agents/art-style-trial/` (ignored scratch).
Final sheets are copied to `sheets/` and motion to `motion/`; `run4/` holds every
cell, frame, clip frame and `receipt-all.json` (source hashes, renderer, adapter).

- Cameras: eye 1.6 m, 75 degree FOV, 1280x720, at 3 m, 10 m and 25 m. Cells are
  nearest crops, 10 m at 2x and 25 m at 4x.
- Light set: south gantry face, sun behind camera. Shade set: north gantry cast
  shadow, sun behind the unit.
- Poses per cell: idle, run, fire, hit, death.
- Motion: run (4 m/s while turning) and combat (raise, two shots, hit,
  collapse), 72 frames at 30 fps per unit and treatment; side-by-side S|A|B|C
  clips as MP4 and GIF.

| Sheet | Shows |
|---|---|
| `sheets/sheet_S.png`, `sheet_A.png`, `sheet_B.png`, `sheet_C.png` | Contact sheet per treatment: 3 units x light/shade x 3 distances x 5 poses |
| `sheets/compare_light.png`, `compare_shade.png` | Idle, fire, death with S, A, B, C side by side per row |
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

A second bake on 2026-10-23 reproduced all four atlases byte for byte
(`bake-verify/`). The capture run printed `art_style_trial: PASS (all)` with no
errors or warnings.

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

Finding: the two games the brief names for the pixel look on live models,
Boltgun and Prodeus, both ship directional sprites lit in 3D, which is
Treatment B. Live low poly 3D with pixel textures (Treatment A) is the Turbo
Overkill, Ultrakill and Dusk family. Sources are interviews, previews and
reviews, not engine documentation.

## Observations

- **S is two games.** Free bodies are smooth, finely textured live meshes with
  no outline; the Clerk is an outlined, stepped sprite. Side by side at 3 m they
  do not share a material language.
- **A** keeps faces and hands readable at 3 m and keeps a true foreshortened
  body in death. Stepped light and the outline pull the free bodies toward the
  Union sprites. At 25 m the one pixel purple outline breaks into purple speckle
  around small figures (most visible on the synthetic and in shade); it needs to
  fade with the texel as C's does.
- **B** reads closest to Boltgun and matches the Union roster exactly. At 3 m a
  160 px cell (about 1.9 cm per texel) blurs faces, and the unlit bake under
  the sprite shader is darker than the live bodies. Death on a billboard
  collapses to a thin blob seen at eye height. Facing pops between 8 cells
  during turns.
- **C** is the most old school in motion (12 fps steps and snapped facings), but
  the 360 line frame turns faces to mush by 10 m and dissolves units into a few
  blocks at 25 m.
- In shade every treatment stays readable at 10 m; B's rim gives the cleanest
  silhouette, A's fresnel band and outline the next cleanest.

## Render cost probe

Sixteen walking actors in the light set, 1280x720, Forward+, AMD Radeon 780M
(RADV), 120 samples after warm up, `run4/receipt-all.json`. One machine under
load; this is relative evidence, not a hardware claim.

| Case | GPU ms median | GPU ms p90 | CPU ms median |
|---|---|---|---|
| Venue only, full frame | 2.41 | 3.04 | 0.58 |
| Venue only, 360 line frame | 1.27 | 1.28 | 0.54 |
| A, 16 live skins | 4.40 | 5.34 | 1.40 |
| B, 16 sprites | 3.07 | 3.29 | 0.70 |
| C, 16 live skins, 360 line frame | 2.89 | 3.14 | 1.12 |

## Costs

All options are $0 in services. Effort figures are estimates for planning,
not measurements.

| Path | Work | Runtime cost | Memory |
|---|---|---|---|
| A for live skins (human, synthetic, Tern, Edda; Splice's rigid presenter separately) | One material swap inside `skinned_character.gd` plus outline distance fade; texture reduction offline or at load; harness, tour, both renderers. About one focused PR | About +0.08 ms GPU per skin over B in the probe; outline is a second draw | Small: 256 px maps instead of 1024 px |
| A for the Union roster | Each Union source is a pose builder that instances a model per pose; live use needs a persistent skeleton, live attack tells, plates and red glow parity for nine units. Several PRs per unit family | As above, for every enemy in a room | Removes atlases |
| B for player bodies | Bake is cheap (two units took 15.5 s); but live skins carry continuous aim pitch, crouch, floor support and seated poses that sprites lose, and Nick chose live meshes on 2026-10-08 | Lowest per actor | Each 2880x4000 lossless atlas is about 46 MB of VRAM, 92 MB with normals |
| C everywhere | A's work plus a 12 fps pose clock and facing snap; frame resolution is a global setting, so faces cannot be protected | Cheapest frame, but blurs everything | As A |

## Recommendation

1. Adopt **A's material for every live skin** (player bodies and named cast),
   with the outline fading out once it would be thinner than one world texel.
   This keeps Nick's live mesh choice, keeps faces and aim readable for the
   multiplayer homage (Counter-Strike, Battlefield 1942 and Halo depend on
   reading where a player is pointed), and closes most of the gap to the
   Union sprites.
2. **Keep B for Union enemies.** It is the technique Boltgun actually uses, it
   is already built, and it is the cheapest at room counts. Raise its close
   range by testing a 192 px cell for officer ranks only, and give death a
   ground plane frame instead of a billboard.
3. **Do not adopt C's 360 line frame for characters.** Keep the 12 fps pose
   clock as a later optional "old school motion" setting to test in play, not
   as the default.

Success for step 1 would be: at 3, 10 and 25 m in light and shade, a live body
and a Union sprite read as one game in `compare_light.png` style captures,
with no purple speckle at 25 m and no regression in the standard tour.

## Limits

- Every unit uses the Clerk's procedural pose set (hands near the hips at idle,
  a small pistol, the Clerk's walk). The trial compares rendering, not
  animation; the shipped free bodies have their own clips.
- Treatment A's palette is a per map k-means reduction, not a hand authored
  ramp; a production version should map to `docs/palette.json` ramps.
- One venue, one machine, no played sequence. Arena Duel alone cannot prove
  the look across campaign interiors or night venues.

## Open questions for Nick

1. Is the split (A for live skins, B for Union enemies) acceptable, or should
   one treatment cover everything even at higher cost?
2. Should the outline stay `outline_purple` on free bodies, or should Union and
   free sides differ (for example red tells only on Union)?
3. Is a 12 fps "old school motion" toggle worth a playtest?
