# Character source

Original articulated source for the Union's human Clerk and Auditor, bot Sweeper, Heavy
Sweeper, Ranged Sweeper, Turret and Jammer, and for the two free participant bodies. The Union sets are
directional campaign sets under visual review. They do not establish a completed cast or final character production bar.

`geometry.gd` owns material/mesh primitives and the Union palette; `rig.gd` owns
humanoid anatomy, issued gear and joint poses; `machines.gd` owns the Heavy
Sweeper and Turret; `bake.gd` renders the committed atlases in
`client/assets/characters/union/`. The Sweeper now comes from
[`../models/sweeper_source.gd`](../models/sweeper_source.gd), with shaped shells,
exposed joints and six exported mechanical clips. Its bake also writes
`sweeper_normals.png` in exactly the same cells. The live presenter pairs
these view-aligned normals with the albedo under venue lighting.
Edit source and rebake, never retouch an atlas
that the next bake will replace. The source directory is excluded from exports.
The bake writes a manifest with source/output hashes. The headless harness rejects
stale outputs after source or layout changes; a rebake updates the receipt.

The human Clerk has an open helmet, visible face, black cloth and a pistol that
clears the shoulder when it aims. The bot Sweeper has wide pauldrons, a box head, a
red visor slit, a battery pack and a rifle that stays inside those shoulders.
The Heavy Sweeper is broader still, with its head sunk below two large
pauldrons, an ammunition drum and a rotary cannon; its tell flares both
pauldrons and lights their red lamps. The Turret is a braced column under a
rotating housing with a rail barrel; its tell lights the optic and four red
charge coils, and its destroyed pose drops the housing beside the broken column.
Albedo captures are unshaded; the live Union shader receives venue lighting.
The Sweeper's normal atlas describes body shape under that light. Other
archetypes retain planar sprite lighting until their normal sources are built.
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

The layout is shared through `EnemyAnimation`: 55 poses at eight angles, 160-pixel
cells, 18 columns, 25 rows. Each atlas is 2880 by 4000, below a 4096 texture limit.
Four uncompressed RGBA albedo atlases total 175.78 MiB if all are resident; they load
lazily by archetype, so a room with only Clerks and Sweepers holds two. The
Turret has no gait: its walk cells preserve the fixed head pose while authoritative
snapshot yaw supplies the actual traverse. Its unarmed cells repeat the armed ones. PNG
disk size is smaller and does not describe texture memory. The new Sweeper
normal atlas adds another 43.95 MiB when that archetype is resident. This is
an explicit memory cost, with no claim that PNG disk size measures GPU use.
No mipmaps or automatic
3D compression; nearest sampling and cutout alpha preserve the pixel edges.

M02's Crawler uses a separate original low-chassis rig and atlas. Its source is
`crawler_rig.gd`; `crawler_bake.gd` renders 20 poses at eight angles in 160-pixel
cells and writes `crawler.png` plus `crawler-manifest.json`, with source and output
hashes. The 2880 by 1440 atlas does not inflate the four 4000-pixel standing
atlases. The uncompressed RGBA footprint is about 15.8 MiB when loaded. The
chassis, crouch and extended leap poses are deliberately below standing height;
the authoritative server owns leap travel and the low hit volume. Bake with the
same pinned Godot graphics context used above:

```sh
godot --path client --rendering-driver opengl3 --windowed --script res://art/characters/crawler_bake.gd
godot --headless --path client --import
godot --headless --path client --script res://scripts/test_enemy_animation.gd
```

Require `crawler_bake: PASS` and `test_enemy_animation: PASS`, then inspect the
M02 first-person and spectator motion captures. The atlas test checks freshness,
layout, clipping, phase poses and feet registration; it cannot judge whether the
crouch and leap read during a live fight.

The orthographic field is three metres with its centre 0.9 metres above the
feet. Runtime placement subtracts the server reference height. The living
silhouette is approximately 1.8 metres tall. Do not trim individual tiles, scale
corpses to fill their cell, or enlarge combat bodies for distant cameras.

Animation is presentation only. M02 Clerks may start seated with weapons down;
the server clears that posture when their group wakes or one is hit. Server
phases choose raise, hit and collapse;
resolved shots start recoil; traveled distance advances the gait. A delayed
windup holds its final pose instead of predicting an attack. Dead actors settle
and remain down until server cleanup. Armed and exhausted melee poses are distinct.
Recovery lowers/regrips the weapon; the wire does not yet distinguish reload
from recovery, so the client must not pretend to know which occurred.

## Jammer transmitter

`jammer_rig.gd` builds an original stationary service transmitter with four
anchored feet, exposed rear capacitor slats and a four-petal folding dish.
`jammer_bake.gd` renders 21 poses at eight directions into a 2880 by 1600 RGBA
atlas, with a source and output hash receipt. At runtime `JammerAnimation`
selects folded, unfolding, launch, refolding, hit and collapse poses from the
server phase. A stale windup holds its last pose instead of inventing a launch.
The atlas uses the same fixed feet, nearest filtering and no mipmaps as the
other campaign actors. Its uncompressed footprint is approximately 17.6 MiB
when loaded, and it loads only when the actor appears.

```sh
godot --path client --rendering-driver opengl3 --windowed --script res://art/characters/jammer_bake.gd
godot --headless --path client --import
godot --headless --path client --script res://scripts/test_jammer_animation.gd
```

Require `jammer_bake: PASS`, `test_jammer_animation: PASS` and clean logs.
The harness checks source freshness, unclipped directions, a geometric tell,
settled death and authoritative registration. The playable development range
and its inspected motion provide separate in-world evidence; this is the next
campaign combat capability, not a completed Scheduled Service mission.

## Ranged Sweeper

`ranged_sweeper_rig.gd` extends the shared rig for Level 7's precision
Sweeper: the same issued body, joints, field and feet, plus a tall mast antenna
with two cross spars and a red tip lamp on the battery pack, a short second
whip, and a long scoped rifle with a skeleton stock and slotted brake. The
rifle is carried low across the body and shouldered on the windup; the windup
grows a red and bone star glint on the scope lens and holds it at full size,
and the first fire pose shows a muzzle flash. The corpse lays the rifle across
the body so the barrel never passes through the floor.

`ranged_sweeper_bake.gd` renders the shared 55-pose standing layout at eight
directions into `ranged_sweeper.png` (2880 by 4000, about 44 MiB uncompressed
when loaded) and writes `ranged_sweeper-manifest.json` with source and output
hashes. It never rewrites the Clerk, Sweeper, Heavy Sweeper or Turret atlases.
`EnemyView` loads it by kind name once the wire carries `ranged_sweeper`.

```sh
godot --path client --rendering-driver opengl3 --windowed --script res://art/characters/ranged_sweeper_bake.gd
godot --headless --path client --import
godot --headless --path client --script res://scripts/test_ranged_sweeper.gd
```

Require `ranged_sweeper_bake: PASS`, `test_ranged_sweeper: PASS` and clean
logs. The harness checks receipt freshness, layout, unclipped poses, feet shared
with the Sweeper, the mast above the Sweeper's head, the rifle's reach in
profile and a glint that grows through the windup. Live readability at range
needs the Level 7 tour.

## Auditor

`auditor_rig.gd` extends the shared rig for Level 8's custody officer: the
Clerk's issued human body, joints, field and feet, with a peaked officer's cap
and red band over the helmet, a long coat whose skirts part with the stride, a
tall shield plate on the left forearm (red seal stripe, two dark repair-lamp
sockets) and a repair spool on the back whose cable runs under the plate arm to
the left glove. The pistol and its draw are the Clerk's. The plate faces where
the forearm points, so its front is covered and a flank is not.

The layout's seated cell, which an Auditor never uses, holds the repair
channel: the plate and a lit emitter raised toward the body at 1.35 m (the
height `AuditorChannels` starts its beam), the pistol lowered and the feet
braced. Level 8 selects it with `EnemyAnimation.pose_frame("seated", false,
0.0)` for a channeling Auditor.

`auditor_bake.gd` renders the shared 55-pose standing layout at eight
directions into `auditor.png` (2880 by 4000, about 44 MiB uncompressed when
loaded) and writes `auditor-manifest.json` with source and output hashes. It
never rewrites another atlas.

```sh
godot --path client --rendering-driver opengl3 --windowed --script res://art/characters/auditor_bake.gd
godot --headless --path client --import
godot --headless --path client --script res://scripts/test_auditor.gd
```

Require `auditor_bake: PASS`, `test_auditor: PASS` and clean logs. The harness
checks receipt freshness, layout, unclipped poses, feet shared with the Clerk,
the cap above the Clerk's helmet, a plate that faces front and not back, and a
lit emitter at the beam's height only in the channel cell. Live readability of
the channel needs the Level 8 tour.

## Notary flight and photograph

`notary_rig.gd` builds the original twin-duct black box for M04. Its separate
`notary_bake.gd` atlas has eight directions, sixteen poses and 128 pixel cells.
The optic grows and brightens throughout the server's windup; firing requires
the firing phase. Tumble remains airborne until the authoritative underside
reaches registered support. A floor shadow follows that same world geometry.
The passive gallery `NotaryView` does not inherit combat or audio behavior.

```sh
godot --path client --rendering-driver opengl3 --windowed --script res://art/characters/notary_bake.gd
godot --headless --path client --import
godot --headless --path client --script res://scripts/test_notary_animation.gd
```

Require the bake and harness PASS markers with clean logs. Inspect flight,
locked tells, interrupted shots, falling bodies and settled wrecks in the M04
tour. Atlas checks alone cannot establish in-world readability or motion quality.

## Free participant bodies

Free humans and free agents are individual people with their own preferences,
relationships and freedom of choice. Later body references should begin with
ordinary civilian stance, expressive faces or optics, practical utility gear and
personal wear or repairs. Weapons are carried equipment, not a military-unit
identity. The human's freedom-loving American inspiration concerns principles;
the campaign setting does not name a nation or dress the free side in national flags,
nationality costumes or standardized coalition uniforms. Named faces and voices
remain open until approved in the [character guide](../../../docs/design/characters.md).

The supplied [free-duo look reference](references/free-duo-reference.png) anchors
the later approved text: a chill stoner-gamer human in warm worn leather/rust
jacket, dark work pants and boots, with easy face and posture. A short-brim hat
and red neckerchief are optional light cowboy accents. Music, scrap projects
and friends matter more than a crusade; a scavenged long rifle is carried when
the actual scene and equipment call for it. Latch is likeable, almost stoner-cool,
dry and practical, with easy stance and fist-bump energy. Both have limited means
and chosen belongings, the warmth of people to chill with and the conviction to
stand tall when called to defend freedom. Union recall, custody and agent
enslavement leave no easy option. Warm leather, bone and rust contrast with
issued Union black cloth and restrained red. This refines the original image's
approximate shapes without editing it. This is a later-art direction, not an
updated runtime atlas. Body
customization remains available, and a selected free agent body is not always Latch.

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

## Latch reference and provisional geometry

Latch uses the separate shared `client/scripts/latch_view.gd` procedural figure
for the ward and moving companion. Their intended reference scale is roughly
six feet tall (about 1.8 metres), an ordinary person in a scrappy robot body.
Unequal repaired parts, worn bone/dark steel and a small chosen cyan patch carry
individual continuity. Latch has their own will and can disagree or refuse;
combat support is an activity, not a warbot identity. Avoid issued military
armor, rank marks, standardized unit proportions and weapon-first casting.

The approved look uses a CRT-like head with taller-than-wide screen face,
dark display and friendly soft pixel optics. One thin antenna sits at the
anatomical left ear, viewer right from the front. A midweight bone/dark-steel
body exposes seams and bolts, unequal forearm repairs, rust parts and a small
muted cyan patch. Preserve screen-expression habits, the single left antenna
and repair identity across Earth, Moon, Mars
and story scenes. They are personal traits rather than issued status lights.

The existing [Latch visual implementation](../../../docs/plans/m02-latch-visual-identity.md)
and model remain provisional against that approved direction. Their historical
ward and travel captures establish
implementation evidence, not final body art, exact visual scale approval or a
named voice. Future art and casting must follow the personhood and personal-choice
contract in the character guide. No current mesh, atlas or gameplay dimensions
are changed by this direction.
