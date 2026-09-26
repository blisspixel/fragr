# Character source

Original articulated source for the Union's human Clerk, bot Sweeper, Heavy
Sweeper and Turret, and for the two free participant bodies. The Union sets are
directional campaign sets under visual review. They do not establish a completed cast or final character production bar.

`geometry.gd` owns material/mesh primitives and the Union palette; `rig.gd` owns
humanoid anatomy, issued gear and joint poses; `machines.gd` owns the Heavy
Sweeper and Turret; `bake.gd` renders the committed atlases in
`client/assets/characters/union/`. Edit source and rebake, never retouch an atlas
that the next bake will replace. The source directory is excluded from exports.
The bake writes a manifest with source/output hashes. The headless harness rejects
stale outputs after source or layout changes; a rebake updates the receipt.

The human has an open helmet, visible face, black cloth and a pistol that
clears the shoulder when it aims. The bot has wide pauldrons, a box head, a
red visor slit, a battery pack and a rifle that stays inside those shoulders.
The Heavy Sweeper is broader still, with its head sunk below two large
pauldrons, an ammunition drum and a rotary cannon; its tell flares both
pauldrons and lights their red lamps. The Turret is a braced column under a
rotating housing with a rail barrel; its tell lights the optic and four red
charge coils, and its destroyed pose drops the housing beside the broken column.
Materials are unshaded so distance reads the shape, not a lighting gradient.
Union issue is black cloth, dark steel, plates one step lighter, and restrained
red on visors, optics, armbands and seals (`union_*` in `docs/palette.json`).
The plates and red accents keep bodies readable in dark rooms. Muzzle flash and
sparks keep palette ember_hot because they are fire, not faction. Neither body type establishes moral status. These are not
free-agent character designs.

Reviewed [reference candidates](references/README.md) now give the next rig pass
a shared human/bot design target. They are separate from the provisional baked
atlases and do not establish finished character art.

## Bake and verify

Use the pinned Godot 4.7.2 binary with a real graphics context. From repository
root, replacing `godot` with the local binary path when necessary:

```sh
godot --headless --path client --import
godot --path client --rendering-driver opengl3 --windowed --script res://art/characters/bake.gd
godot --headless --path client --import
godot --headless --path client --script res://scripts/test_enemy_animation.gd
```

Require clean logs and `character_bake: PASS` / `test_enemy_animation: PASS`.
On Linux, the bake needs a display or the existing Xvfb approach from
`tools/qa_tour.sh`. Headless rendering cannot bake usable pixels. Windows OpenGL
on the AMD Radeon 780M was used for the first bake, 2026-09-20. Exact pixels can
vary across drivers; tests assert bounds and behavior, not a driver-specific hash.

The layout is shared through `EnemyAnimation`: 54 poses at eight angles, 160-pixel
cells, 18 columns, 24 rows. Each atlas is 2880 by 3840, below a 4096 texture limit.
Four uncompressed RGBA atlases total 168.75 MiB if all are resident; they load
lazily by archetype, so a room with only Clerks and Sweepers holds two. The
Turret has no gait: its walk cells are a head traverse that plays on phase time
while the server turns the head, and its unarmed cells repeat the armed ones. PNG
disk size is smaller and does not describe texture memory. No mipmaps or automatic
3D compression; nearest sampling and cutout alpha preserve the pixel edges.

The orthographic field is three metres with its centre 0.9 metres above the
feet. Runtime placement subtracts the server reference height. The living
silhouette is approximately 1.8 metres tall. Do not trim individual tiles, scale
corpses to fill their cell, or enlarge combat bodies for distant cameras.

Animation is presentation only. Server phases choose raise, hit and collapse;
resolved shots start recoil; traveled distance advances the gait. A delayed
windup holds its final pose instead of predicting an attack. Dead actors settle
and remain down until server cleanup. Armed and exhausted melee poses are distinct.
Recovery lowers/regrips the weapon; the wire does not yet distinguish reload
from recovery, so the client must not pretend to know which occurred.

## Free participant bodies

`player_rig.gd` extends the same rig with the two bodies a player can choose: a
free human and a conscious embodied agent in a synthetic body. They share the
rig's joints, poses, field and feet registration, and none of the Union issue:
no black cloth, red, serials, pauldrons or visor slit. The human wears a bone
shirt under an open warm-leather jacket, a rust scarf and a cyan patch and
armband, with a visible face and hair. The synthetic body is a bone shell over a
gunmetal frame with a leather harness, an ember scarf, rust repair plates, two
round cyan lenses and one magenta-tipped antenna. Both are outlined in outline
purple. Neither body establishes moral status.

`player_bake.gd` writes `client/assets/characters/free/human.png` and
`synthetic.png`: one row of 160 pixel cells, four idle breaths then four walk
frames, unarmed, because the runtime weapon sprite is held at the hands. It also
writes a manifest with source and output hashes, which `test_player_body.gd`
checks for freshness and for the absence of Union red. A review sheet beside the
Clerk and Sweeper goes to `.agents/characters/free-bodies/`. Bake the same way:

```sh
godot --path client --rendering-driver opengl3 --windowed --script res://art/characters/player_bake.gd
```

Run the main and maintenance M01 tours after changes. Inspect attack and death
sequences, facing from multiple sides, occlusion, feet, both renderers, and
spectator eyes. The atlas harness cannot determine whether motion looks good.
