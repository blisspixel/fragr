# Weapon and character continuity audit

Status: complete read-only audit, 2026-10-05. Corrections and played acceptance
remain open. This audit uses the proposed Pistol
selection snapshot `8879b5ee`, not a claim that its artwork has shipped.
Other selected pictures are retained unchanged. No runtime art, source, scale,
hand rig, story image or provider request changes in this lane.

## Method

Inspect the seven selected idle pictures, actual HUD canvas and control
transforms, including the separate Fists presenter and Shiv rest scale. Build
a CPU contact sheet from the unchanged pictures at a common native scale and
at the actual HUD layout scale. Mark visible palm and wrist spans manually,
separating pose and perspective differences from obvious disproportion or
material mismatch. These are editorial measurements, not a new automatic
personhood or anatomy threshold.

Inventory every selected story image through the scene manifests and distinguish
existing images, missing-file text fallback and unselected character references.
Compare named characters only against their current canonical identity and
source. The opening workshop image is owned by a separate correction lane;
this audit does not edit it. Actual gameplay and GPU HUD captures remain separate
evidence from a CPU picture/layout study.

## Selected hands and actual layout

Every selected idle picture is 241 by 180 pixels. The common gun control is
482 by 360 logical pixels, nearest filtered and aspect centered. The project
uses a 1920 by 1080 logical canvas. The measured 1280 by 720 window applies
the actual viewport stretch of two thirds, giving four thirds of a physical
pixel per source pixel. Idle bob is disabled for this comparison. The ordinary
12 logical pixel bottom overlap still clips the last six source rows. These
are actual control measurements, not a resized screenshot assumption.

Fists use separate left and right controls with 120 and 121 source pixels,
rendered at 240 and 242 logical pixels. Their resting source scale matches
the guns. A punching arm has its own deliberate forward enlargement, so a
punch peak is not a resting hand-size comparison. Shiv applies an additional
1.3 resting scale to the whole picture around its lower-right pivot. Its
hand therefore grows with the blade, independently of the original drawing.
Sniper's scoped view hides the held picture; this comparison is unscoped.

The CPU projection multiplies each actual control transform by the viewport
stretch, as defined by the official [Viewport transform documentation](https://docs.godotengine.org/en/stable/classes/class_viewport.html#class-viewport-method-get-stretch-transform).
It retains the default logical canvas instead of forcing a smaller canvas.
It is not a renderer frame, gameplay comparison, performance measurement or
proof of recoil presentation at every resolution.

| Weapon | Selected idle path below `client/` | Visible continuity assessment |
| --- | --- | --- |
| Pistol (Tack) | `assets/weapons/pistol-sprite-20261005/pistol_idle.png` | Proposed new drawn picture. Rust-brown stitched gloves match the legacy family, with both hands meeting at the compact grip. |
| Rifle (Flechette) | `assets/weapons/viewmodels/rifle_idle.png` | Restored drawn picture. Same dark cuff and leather palette; receiver hides most of the firing hand. |
| Shotgun (Scatter) | `assets/weapons/viewmodels/shotgun_idle.png` | Strong reference for dark glove edges, stitching and readable fingers. Foregrip changes the visible palm angle. |
| Rail | `assets/weapons/viewmodels/railgun_idle.png` | Selected original, not the offline candidate. Same drawn leather family; gun hides much of each hand. |
| Sniper | `assets/weapons/sniper-source-20261004/sniper_idle.png` | Clear material and craft mismatch: tan flat polygon gloves and broad tan sleeve, little visible stitching, compared with the other selected hands. The wrist is cut off, preventing a trustworthy cuff-width comparison. |
| Fists | `assets/weapons/viewmodels/fists_idle.png` | Same rust-brown leather and dark cuffs; larger exposed knuckle backs are expected from clenched, unobstructed hands. |
| Shiv | `assets/weapons/viewmodels/shiv_idle.png` | Same drawn glove finish, but the whole hand is enlarged by the explicit 1.3 idle presentation scale. |

The following manual source-pixel landmarks identify the visible glove-back
centre and cuff short axis. They are approximate to four source pixels.
Different wrist rotation, foreshortening and gun occlusion prevent treating
these spans as real-world palm dimensions or an anatomical pass/fail test.
The marked contact sheet records the endpoints, cyan glove centre and yellow
wrist/cuff rather than using a color classifier to guess anatomy.

| Weapon | Visible glove-back centre `(x,y)` | Cuff endpoints `(x,y)` | Approximate cuff span, source pixels | Display span at 1280 by 720 |
| --- | --- | --- | ---: | ---: |
| Pistol | `(133,124)` | `(72,149)` to `(108,165)` | 39 | 53 |
| Rifle | `(80,124)` | `(51,159)` to `(82,174)` | 34 | 46 |
| Shotgun | `(80,135)` | `(51,163)` to `(83,178)` | 35 | 47 |
| Rail | `(87,139)` | `(62,164)` to `(84,179)` | 27 | 36 |
| Sniper | `(104,151)`, exposed right palm | Wrist below canvas, other palm occluded | Not measured | Not measured |
| Fists, left | `(84,117)` | `(47,149)` to `(73,165)` | 31 | 41 |
| Shiv, right | `(160,119)` | `(164,160)` to `(191,150)` | 29 | 50, including 1.3 scale |

The small visible Rail cuff is oblique and mostly hidden, not evidence of a
smaller character. The definite scaling inconsistency is Shiv's separate HUD
scale; the definite finish inconsistency is Sniper. Fixing either should
preserve useful grip poses, then compare all resting hands at the actual HUD
and ordinary recoil or gesture peaks. Changing the shared image control to
match one weapon would resize all other guns.

## Story pictures and named identity

All 16 selected scene manifests contain 30 shots, with four existing unique
image files and three missing unique image paths. Missing images use the
existing text presentation in `scene_player.gd`; they are not hidden portraits.
No separate selected named portrait UI or portrait asset was found in the
current story presenter and scene manifests.

| Existing selected image | Used by | Identity review |
| --- | --- | --- |
| `assets/story/stills/opening/workshop.png` | Opening HOME and CHOICE | Actual older Latch has a blank compact helmet-like head. It lacks the canonical dark CRT face, friendly pixel expression and single left-ear antenna. Must be replaced using the same Latch identity as gameplay. The separate opening correction owns this image. |
| `assets/story/stills/opening/annex.png` | Opening PURSUIT | Architecture, no named body or portrait to reconcile. |
| `assets/story/images/m06/moon_port_arrival.png` | M06 arrival MOON and PORT | Lunar port and carrier, no visible named face. Character continuity does not require replacing this image. Venue/source architecture consistency is a separate art review. |
| `assets/story/images/m06/lunar_transit_departure.png` | L06 to L07 TRANSIT, L07 to L08 DEPOT, M07 arrival TRANSIT | Lunar interior/exterior scene, no named face. Reuse is explicit, not three different character depictions. |

Missing paths are opening `address.png`, opening `recall.png` and
`stills/l01_l02/key.png`. The latter covers LEDGER, SHIFT and WARD, with Mara
speaking in SHIFT. M03's MAST has Latch speaking but no picture. Speech does
not mean a generic background figure is that named person. Older artwork
under `client/art/story/opening/` remains unselected development material.

The canonical identity is defined in `docs/lore/cast.md`. The following
gameplay gaps are separate from the workshop picture:

| Named character | Current visible/source seam | Continuity finding |
| --- | --- | --- |
| Latch | `latch_view.gd`, `latch_source.gd`, `assets/models/latch_stylized.glb`; campaign companion route in `player_pawn.gd` | The live model retains the screen, antenna, uneven bone/rust repairs and lean adult silhouette of `references/latch-stylized-v2.png`. The prior actual M02 witness shows this model, not a body-strip fallback. Its measured weighted height is 1.799972 m. This does not establish that every camera or pose feels sufficiently substantial. |
| Second captive and side captives, M02 | `m02_ward.gd` twelve-part local figures | These are different provisional captives, not smaller or alternate Latch identities. Their block forms remain an obvious art gap. The shot-body correction does not turn them into accepted character artwork. |
| Renn, M08 | `m08_archive.gd`, `RennProvisional` | Generic tinted human participant strip rather than Renn's narrow issued coat and registry case. No reviewed named portrait/source was selected in this snapshot. |
| Orrin, M08 | `OrrinBackupCase` | Canonically a backup container first. Absence of a humanoid portrait or body here is correct; later restoration must be explicit. |
| Tern, M09 | `m09_berth.gd:102` | Actual conditional selects synthetic only for `splice`, otherwise human. Tern therefore receives a generic human strip despite canonical free-agent identity. This is a concrete body-selection error, not merely a missing portrait. |
| Edda and Splice, M09 | `m09_berth.gd`, tinted shared strips | Human/synthetic category is appropriate, but named medical satchel/apron and compact tool-rack/magenta-wrist identity are absent. New named references are development references, not selected runtime figures or portraits. |
| Mara | Canon rust utility coat and route case; text-only selected SHIFT | No actual selected portrait to compare or replace. A future image needs her own reference, not a generic human face. |

The actual M02 release witness is retained under
`.agents/character-shot-occlusion-20261005/.agents/m02-shot-witness-first/`.
`13_authoritative_releasing_body_before.png` shows live Latch and the much
simpler second captive side by side. `companion-body-source.json` records
`LatchView`, one weighted mesh, one material and zero Sprite3D descendants.
The later `13_authoritative_releasing_body.png` foreground figure is the
second captive after Latch has walked out of frame. Do not use that frame to
claim a Latch presenter fallback.

## Immutable sources and receipts

Idle SHA-256 values at the inspected snapshot:

```text
Tack       2ae7bcceaee5a84f35fb6356ae1ee06d136d59e189be81b85d2995b2e6bc789d
Flechette  92b7ef9d7bd8d3216c3967c9ea943aa726b7c04889bb9492ca649f0a6d6cabc0
Scatter    d66c7e0aa94818adcd3e30f26de18c7e426ec8e5a08c1914fcbe1d3b66756011
Rail       8392655eebcda1a9eb14f47af62693388cc6faa834118629c545890133e92f3e
Sniper     4b1da75e12e786d426884de9444731663695de8f8ffdddb23130969ff411d077
Fists      f505a178d8f834dafdf834739fe92787bc1a5bed6326262868df93dbc81c102e
Shiv       e7a13b4bbc918ace97910ac9f3ec1c44fecdc0e2a6e7a0b8920804ff8d5035c8
```

Latch live source SHA-256 is
`8b1ec57399ec51a70617a42c9777a04347170d5ddf78dc54b67649b3f6992951`;
canonical reference is
`0dfea3de518111bd761b7e8ae191d133aa3a7220d248c52f37eab16b948a4b72`.
The separately owned workshop correction supersedes the inspected historical
image SHA-256
`9258247d09f7a046875b53f924d1e1c659182307e9162014314682d941bdddde`.

Private reproducible CPU evidence lives under
`.agents/weapon-character-continuity-20261005/.agents/continuity-final/`:

```text
audit.json                 af1d0a4bcdac1bab53ff735483709035c3763f3ad5799d62c5a2ae0d6bedb8c3
landmarks.json             d0b81cf3326a6bed33baa31dc926702703f9a9b0f5160287fb5f628dc77e1db2
native-contact-sheet.png   0bf7299f3257b27f40e6fbaf333838531025a3f629b5e30b5ebc2fdabe5d3d8f
hud-contact-sheet.png      57aca35bf3ba10ebf7dfe912aad94f3c45cc72c638403519e94370c5b0bd72b4
landmark-contact-sheet.png f22ce5acad4c7bcf4a5febb6d3f8a50858cd3e0e64ea0e39f395f1cfa51b0dd9
```

Godot 4.7.2 headless import, final layout audit, source-grid generation,
landmark recording and receipt inventory each exit 0 with clean error logs
and their own PASS. The first projection omitted viewport stretch and made
an empty sheet; the second forced a different logical canvas. Both diagnostic
logs are retained and neither is valid actual-HUD evidence. The final script
records the real logical canvas, physical window and stretch transform, then
projects unchanged pixels through those transforms. No network/native child,
hardware renderer, provider call or runtime asset mutation was required.
