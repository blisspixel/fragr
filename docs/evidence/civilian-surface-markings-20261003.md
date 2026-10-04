# Civilian surface markings

Recorded 2026-10-03. [Bounded plan](../plans/civilian-surface-markings.md).
**Status:** implemented with inspected ordinary-input art subsets, focused
material checks and complete final local client checks passed.
[PR #347](https://github.com/blisspixel/fragr/pull/347) owns final combined
integration and CI.
**Spend:** $0. All textures were already local.

## Material boundary

Low Water enamel previously inherited the shader's red warning pinline despite
its civilian venue palette. It now uses muted taupe trim. Other Low Water material
markings use their existing venue paint, with no trim emission. Maintained care
possessions, repaired plaster and the workshop's three paint chips remain.

Lunar town enamel selects the existing pressure-bone wall and worn-deck horizontal
textures. Its wall blend is 30 percent, preserving pressure-shell history without
the initial candidate's stronger repeated detail. Muted gray paint replaces the
red dwelling pinline, with no trim emission. Repair plates remain selected for
lift panels. Records surfaces retain their existing institutional ceramic.

The town's common ground receives a separate material instance with worn deck,
muted gray markings and zero trim emission. Its shared shader, pixel ribs, joints
and cached nearest-filtered textures remain. Explicit service-steel solids such
as the curfew post and vault barriers retain dark surfaces and red markings.
The floor duplicate cannot modify their material instance. Port/archive and all
other venues retain their earlier textures and ground assignment. Actor outfits,
map bytes, geometry, lighting settings, gameplay and timing are unchanged.

## Local checks and capture conditions

`test_environment_textures.gd` passes with exit 0 and a clean error log. It checks
real local images, nearest storage, cache reuse and wrap edges; actual selected
wall/deck paths; civilian versus issued shader parameters; independent ground
materials; actual `ArenaCover` floor/solid assignments; non-town replacement;
glass isolation and missing/unknown venue fallback. The initial expanded test
referenced a variable outside its scope; that failed diagnostic is retained and
the corrected final focused harness passes.

The complete stable-source `tools/godot_check.sh` exits 0 with `Godot checks:
PASS`, all 231 script parses and 107 harnesses passing. All 339 expected labels
are present, with no script/runtime errors or failures. The final checker uses
pinned console and GUI binaries beside the private matching release server,
including actual local launch and mission harnesses. Its receipt verifies the
final implementation, test, shader and map hashes remain unchanged through the
run. The final checker log SHA-256 is
`90f9f0d77ba00d2aeb6f25556b2ac5ee7b2784abd5ccb4ff950e7c9e4c275f85`.
This local gate precedes the separate combined M07-to-M08 carry integration
and its final CI/client gates.

The source checkpoint is `904249e14eb743fdb95c61b0c66c47f32b1398be`, based on
the accepted M04/M06 integration plus the accepted M07 branch. A private matching
release server has SHA-256
`3398950183dd911aebdabc659a414fbdfad2b349c418cb6745ec7d11c259d4c9`.
Neither root nor earlier capture binaries were overwritten.

Both art subsets use Godot 4.7.2-stable Compatibility on AMD Radeon 780M at
1280 by 720, zero rule bots, seed 42 and assisted difficulty. Human-role ordinary
input reaches every photographed position. No detached cameras, teleports,
resource grants, changed encounter checks or departure claims are introduced.
Settings, records and runs use isolated paths; automation releases the pointer.
Owned native and renderer processes are closed.

| Art subset | States | Combat probes / confirmed guards | Walking goals | Recorded result |
|---|---:|---:|---:|---|
| M04 workshop through clinic | 14 | 3 / 9 | 47, all arrived | 0 deaths, 0 HP lost, 0 armor lost, 0 dry triggers, 1 secret |
| M07 tunnel through dwelling window | 10 | 3 / 10 | 23, all arrived | 0 deaths, 20 HP lost, 0 armor lost, 0 dry triggers |

Both exit 0 with their actual `qa_tour` completion markers, clean logs and no blank
captures. The M04 subset retains the first 14 states of the accepted enclosure
variant, including clinic opening and patient release. It was captured after the
final Low Water parameter change and before the added M07-only ground split;
that later split does not change Low Water parameters or material assignment.
The M07 subset repeats its first 10 canonical states from the final material and
ground source. These subsets preserve the earlier complete route evidence rather
than claiming new full mission completions.

Private receipts live under `.agents/civilian-surface-markings/.agents/`.
From that worktree, the retained capture commands are
`./.agents/run-art.ps1 -Venue m04` and
`./.agents/run-art-final.ps1 -Venue m07` in PowerShell. Each starts only its
owned matching server and runs the standard `qa_tour.gd` with an isolated manifest.
The M04 manifest SHA-256 is
`b1378bfddfdd2d1e65150975619681ee3b46129b05a7712c6ad5763a8a8ed07b`;
the final M07 manifest is
`30d725275a35b9a52790253a6ecf86540cb949a7779a77c0747af982e63663f2`.
The preliminary M07 capture retains its red ground stripes and 55-percent wall
blend. It was superseded by the final repeat, not overwritten. The preliminary
client checker was explicitly interrupted after this scope expansion and is not
an acceptance gate; the complete stable-source repeat has its own log.

## Inspected player-height comparisons

Earlier accepted captures supply the before frames. The same authored stops and
look targets supply the after frames; ordinary movement and live combat can
change camera feet, poses and HUD values slightly. These are visual comparisons,
not identical-frame pixel diffs. The earlier M07 capture also uses the earlier
Clerk art; the combined after client includes the separately accepted stylized
Clerk. Uniform differences are not a result of this material increment.
Public PNG copies preserve captured image bytes.

| Place | Before | After | Inspected change |
|---|---|---|---|
| Workshop | [Before](../screenshots/civilian-surfaces-20261003/workshop-before.png) | [After](../screenshots/civilian-surfaces-20261003/workshop-after.png) | Quiet wall and locker trim; paint-chip colors and keyed sign remain clear |
| Care counter | [Before](../screenshots/civilian-surfaces-20261003/clinic-before.png) | [After](../screenshots/civilian-surfaces-20261003/clinic-after.png) | Muted wall/counter edges support jars and folded linen |
| Town and vault | [Before](../screenshots/civilian-surfaces-20261003/town-before.png) | [After](../screenshots/civilian-surfaces-20261003/town-after.png) | Quiet dwelling fronts and common deck contrast with retained red issued barriers |
| Dwelling window | [Before](../screenshots/civilian-surfaces-20261003/window-before.png) | [After](../screenshots/civilian-surfaces-20261003/window-after.png) | Pressure-shell history, muted seams and worn deck frame the existing glass and civilian gesture |

Large wall grids, rectangular building silhouettes, provisional civilians and
the stronger lighting composition remain wider art work. This correction
establishes material identity, not final map quality, fresh-player fun or broad
hardware performance. Integration CI, shared status documents, main and desktop
publication belong to the parent integration pass.
