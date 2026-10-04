# Stylized Sweeper source and runtime sprites

Local source and sprite evidence, 2026-10-04. Integration and full combined CI
remain separate gates. This lane makes no paid calls.

## Selected source and physical posing

The prepared `client/art/models/candidates/sweeper.glb` retains 12,458 triangles,
18,281 vertices, 24 bones and embedded nearest 1K material maps. The selected
walking rig contains the actual `Armature|walking_man|baselayer` clip, sampled
into a 1.0667-second `walk` animation with 23 tracks. The prepared body is 1.8 m
tall. It uses the shared source loader, cache and two-bone arm helper from the
`a48fd5b4` increment.

`sweeper_skinned_source.gd` poses that skin and the existing issued Rifle mesh
together. Both wrists reach the same weapon anchors, within 1.2 cm in all 21
tested armed idle, walk, raise, fire, recover, hit and death samples. The support
wrist cups the foreend rather than inheriting elbow twist. Windup raises the
held gun, recoil preserves its grip, recovery returns to its carried position,
and a hit moves the torso. Unarmed poses remove the gun and strike forward.
Walking samples the actual skin, removes horizontal root travel and retains
vertical gait. The terminal body and gun settle horizontally above the floor;
the harness checks weighted corpse vertices as well as root transforms.

The first replacement failed two existing silhouette assertions. Its front
outline was 44 pixels at both rest and aim, narrower than the retained Clerk's
45-pixel rest and 51-pixel aim. A reviewed horizontal source calibration of
1.38 produces 61 pixels at rest and aim, with unchanged height, camera field,
sprite scale, feet registration, rifle anchors and authoritative collision.
Front, side and corpse views are inspected. The broader issued shell remains
smaller than the Heavy Sweeper's shoulder span and distinct from the lean free
civilian direction.

The earlier `sweeper_source.gd`, exported mechanical GLB and rigid clip library
remain unchanged. The new source selects the actual directional game atlas;
the game still renders those directional sprites, not the offline skinned GLB.
No server geometry, attack timing, damage, ammunition, roster or save bytes
change in this art pass.

## Bake scope and source checks

The standing layout remains 55 poses, eight directions and 160-pixel cells,
2880 by 4000 pixels per atlas. A bounded `bake.gd -- --kind sweeper` selects only
the Sweeper albedo and paired view normals. The no-argument full cast workflow
remains available. Its receipt records rendered roles, retained roles and the
previous receipt's source hashes. It rejects invalid cast arguments and
unknown, duplicate, missing or changed retained outputs.

The accepted Clerk albedo/normal, Heavy Sweeper and Turret images retain their
exact main bytes. A first full-cast attempt changed decoded pixels for those
roles on this renderer; that attempt's log is retained privately, and those
outputs are discarded. They are not described as newly rendered here. The GLB
import keeps embedded maps, following the existing Clerk preset. Standalone
extracted material PNGs are not selected or committed.

Focused gates pass with clean exit 0 and each harness's own PASS marker:

- `test_sweeper_skin`: retained skin, exact rifle anchors, true gait, horizontal
  root registration, recovery, hit, unarmed strike, weighted corpse bounds,
  paired alpha across every direction/phase and path-keyed cache identity.
- `test_enemy_animation`: unchanged live phase selection and near/far outline
  gates, all standing atlas cells nonempty/unclipped and current source/output
  receipt hashes.
- `test_clerk_source`: retained Clerk skin, grip, gait, melee, seated posture
  and paired alpha.
- `test_model_assets`: unchanged historical mechanical export, its animation
  contracts, pump articulation and source receipts.

The invalid-kind negative check exits 1 with its expected diagnostic. Private
source inspection initially used a center-pixel black-frame check that rejected
valid black steel pixels. The failed logs are retained; the corrected fixture
checks its deliberate corner background and exits cleanly after all 16 views.
No extra observer or gameplay scene lifecycle override is involved.

## Ordinary-input combat

The first bounded M01 proof passes all three original arrival, Clerk and intake
states. The derived intake state walks without capture-controller shooting,
then waits for one actual enemy shot and requires rendered windup, firing,
recovery, hit and dead phases. It keeps both named Sweepers, finite supplies,
normal movement, geometry and server attack timing. The standard QaTour
lifecycle is unchanged. This is accurate-aim art authoring evidence on Assisted,
not fresh-player difficulty acceptance or a complete M01 departure proof.

Captured at 2026-10-04 11:36:39 UTC, Godot 4.7.2-stable Compatibility/OpenGL on
AMD Radeon 780M, 1280 by 720. It has three successful walking arrivals, all
nonblank states and clean renderer exit 0. The matching immutable native server
loads the unchanged source map on isolated port 16885. Owned server/renderer
processes are cleaned. The player defeats the intake Clerk plus both named
Sweepers with 15 finite Tack attacks in the overall subset, retains 100 HP and
35 bullets, and has zero deaths, HP/armor lost or dry triggers. The Sweeper
probe records 11 player attacks and one real enemy attack.

| Captured Sweeper phase | Server tick |
|---|---:|
| Moving | 399 |
| Windup | 441 |
| Recovery | 445 |
| Firing | 496 |
| Hit | 501 |
| Dead | 547 |

Named deaths are west at tick 542 and east at 547. The real firing image shows
a resolved trace striking cover; the player takes no damage. The hit frame
shows the physical reaction and resolved damage. The first dead frame is the
beginning of a fall; the final subset state observes settled body frame 27,
mostly hidden behind the counter. Across-room shape and red optic are visible,
but this 14 to 18 m encounter does not establish close hand/corpse quality.
A fourth ordinary walking state passes all the same gates and six total
arrivals, but takes three seconds after the encounter wait. The existing server
retires ordinary corpses at kill plus 40 ticks (two seconds), so its near floor
frame correctly contains no body. That route/receipt is retained as traversal
evidence; it does not prove near settled-body art.

A corrected pre-kill approach reaches the same gap before the combat probe and
does capture a settled skin/rifle on the actual floor. It passes all gameplay
and phase gates at 100 HP. Its renderer exits 0 but reports two 349,524-byte
GLES texture leaks during teardown, so the strict standard error gate rejects
that run. The failure is preserved. A byte-identical route repeat with the
unchanged standard lifecycle passes with clean exit 0 and no error diagnostics.
No lifetime extension, observer, error suppression or source/gameplay change
is used to reach the close view. A single successful repeat does not establish
the cause of the earlier two-texture retirement failure.

The clean close repeat was captured at 2026-10-04 12:01:45 UTC on the same
renderer, hardware and resolution, isolated port 16888. All three nonblank
states, five ordinary walking arrivals, both named Sweeper kills and the five
required windup, firing, recovery, hit and dead phases pass. The subset defeats
the Clerk and both Sweepers with 13 finite Tack attacks, 11 damaging attacks and
220 HP damage. It finishes with 100 HP, 37 bullets, zero deaths, HP/armor lost
or dry triggers. The Sweeper probe records ten player attacks and one real
enemy shot. West dies at tick 500, east at 551. Captured phase ticks are moving
454, windup 436, recovery 442, firing 479, hit 484 and dead 500. A later actual
dead sample reaches frame 27 at tick 564, 6.09 m from the player.

The close firing/hit views show both held rifles and readable mechanical
silhouettes. The final settled body is partly occluded by a cabinet edge after
ordinary enemy movement; this proves the live floor pose is selected, not a
fully unobstructed near-body inspection. The rejected earlier attempt provides
a clearer settled body/rifle image, labeled as failed-run visual evidence.
Detached weighted-vertex and source views separately verify full corpse shape.
All owned capture/server processes are cleaned after the repeat.

## Reproducible inputs and scope

Source checkpoint: `6c7e68923010876dbc6172cfd9cceb45e168192b`, based on main
`a8611d04` plus the unchanged shared-loader dependency.

| Artifact | SHA-256 |
|---|---|
| Prepared skin | `5c76a57ee1c4239d546c41f65e2eebfee002def27951e991dec2a5927c88a3bd` |
| Posed source helper | `b25c659d1ef945c431ea97c587608439c584611ee3d5070febac15466788f3dc` |
| Embedded import preset | `d43e6f95d643536b591127c31dbd8590d8c3b892fb55d37caf6bb3a789dffc64` |
| Selected albedo | `72ba2324123eff6a28050a04702f73849f04f0ef400b35ad2479a35018086218` |
| Selected normals | `68b03b944cfc844268ec1a05e83445406c0db3829e8b0e84249ec9f6a77dd71d` |
| Standing receipt | `bf88034ba2bd90e6d5262a0524f25c3721d0ced548a1f4aff2213e57a0599505` |
| Unchanged M01 map | `25e605c67cf4e97c8bfb2a980ffa9bee6b39140a431ae99f86f61ff5fec9f30e` |
| Matching native server | `a54543c362f3c89e2e2d9636d22dd1d5cda2dc320646c0ba52d239939c6bcd3f` |
| Three-state route | `12f2bcbd103f0a52529b3d5aec0132d83402b4b374699c315ce4dd7be9ec194c` |
| Three-state capture receipt | `086826a3833a4c6ed0fa968c661465aacbbcedc5071730cd962efd2552bd28f3` |
| Three-state client log | `1eae74d042374a1e04fbb600a5259609e036f8d0066da60fa332dfbd7b72d382` |
| Close approach, both attempts | `bfe92e7c995bc2eee2cccc6752344c2ba9cba1d9a0f48ee5931d4a4c4e1f0131` |
| Clean close receipt | `cf22ddb22d6c649b183c437f431b289ae1d554e18a635503d1158b23888d51bb` |
| Clean close client log | `59e47f75bd6d33dbbd0201302efcb16ee8d02266a9eb17a535cdc38943abfb36` |
| Rejected close receipt | `1975335803e3e2b9d87158793ca113657e843b0b82854d8356c8a53ef382cd06` |
| Rejected close client log | `87f654bb5b2755c2d9fabd25ef62b1fe78b4c03d174c59999776d7f9122c6428` |

Private receipts/logs are under `.agents/sweeper-stylized-source-20261004/.agents/`
in the repository checkout. Final focused source, atlas, Clerk and mechanical gates
pass with no error diagnostics. `m01-sweeper-1` contains the clean across-room
proof; `m01-sweeper-2` the clean post-retirement traversal; `m01-sweeper-3` the
rejected close proof; `m01-sweeper-4` the clean byte-identical close repeat.
Committed source bytes are independently
checked against the bake receipt. A complete combined client checker and
implementation CI remain required before integration.

## Inspected images

[Fixed-scale cast comparison](../screenshots/sweeper-stylized-20261004/cast-comparison.png):
columns are historical Sweeper, retained Clerk, selected Sweeper and retained
Heavy. Rows are front rest, front aim, side aim and settled death. This compares
decoded atlas cells at nearest sampling, not a gameplay camera or lighting test.

[Held rifle](../screenshots/sweeper-stylized-20261004/source-rifle.png) and
[settled source](../screenshots/sweeper-stylized-20261004/source-settled.png) are
detached 900-pixel source inspections under fixed light. They show skin/weapon
attachment and corpse shape, not a played scene. The
[actual firing](../screenshots/sweeper-stylized-20261004/intake-firing.png) and
[actual hit](../screenshots/sweeper-stylized-20261004/intake-hit.png) are unmodified
player-height combat frames from the first real three-state subset.

[Close firing](../screenshots/sweeper-stylized-20261004/intake-close-firing.png)
and [partially visible settled body](../screenshots/sweeper-stylized-20261004/intake-settled-partial.png)
are unmodified player-height frames from the clean close repeat. The
[clearer settled body](../screenshots/sweeper-stylized-20261004/intake-settled-rejected.png)
comes from the rejected close attempt. Its actual image is useful for the floor
pose, but its error-bearing run does not count as clean rendered acceptance.

## Limits

The supplied skin has no separate finger bones. Its fingers remain fixed
mechanical shapes; independent finger closure is not claimed. Humanoid skinning
can flex hard plates slightly during gait. Dense metal edge detail remains a
refinement target at small fighting distances. This replaces one ordinary
Sweeper, not the Ranged or Heavy Sweeper source, full roster or entire game's
art acceptance. Wider map composition, lights and civilian surfaces are not
modified by this lane.
