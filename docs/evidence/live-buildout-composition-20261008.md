# Live characters, foundry and Conquest composition

Status: implemented locally, verified on 2026-10-08. This continuation follows
the [open-issue composition](open-issues-composition-20261008.md). Its earlier
checks remain historical. Nick requested another parallel split for character
models, the M12-M14 development slice and multiplayer mode work, and selected
live animated meshes for the character pass.

## Implemented scope

The [live presenter plan](../plans/live-character-presenters-20261008.md) selects
the retained free-human and free-synthetic bodies for moving players and the
prepared named Tern for current M09/M10 mission facts. The shared weighted
presenter follows accepted feet, facing, movement, crouch, driver/gunner stance
and death. First-person mode hides the full skin and carried effects. Existing
strip previews and a missing-model fallback remain. Offline weighted bounds
produce compact support curves rather than scanning skin vertices during play.
The models, embedded textures and support document are packaged separately from
excluded offline art sources. Server outcomes, saves and protocol are unchanged.

The first renderer pass found fixed-Y weapon profiles discarding accepted pitch.
The live carried plane now preserves the actual gun axis while facing the camera
and handles end-on views. Retained raster controls distinguish steep actual aim
from the original horizontal profile. Measured painted grip offsets improve the
wrist attachment; the source hands still need individual grip refinement.
Independent failure probes also reproduced stale carried ownership and reflected
direction after a missing replacement model, plus a dead shooter's hidden
resolved flash. Actual accepted-state fallback and real-pawn shot regressions
cover the fixes. These presentation regressions do not grant combat outcomes.

The [foundry receipt](m13-foundry-development-20261008.md) records M13's 121
solids, nineteen finite stocks, 22 existing guards and five ordered groups.
Four native checks cover 118 routes, both stairs, actual finite-magazine combat
and reset. An eighteen-state rendered route uses 77 walking waypoints. Six
selected full-size originals were independently inspected. M12/M14 source bytes
are unchanged. All three remain standalone development maps without connected
mission progression, rescues, new-role substitutions or a simulated lift.

The [Conquest receipt](conquest-coordination-20261008.md) records stable useful
capture work, threatened-site defense and reassignment through ordinary roster
churn. Twenty focused checks include actual Session movement, combat, contest,
respawn continuity, obstruction and full ticket exhaustion. The planner runs
once per controller pass and adds no navigation search. Capture and ticket
arithmetic remain unchanged. Its controlled complexity fixture establishes
neither network capacity nor a completed human island route.

## Composed verification

The [machine receipt](live-buildout-composition-20261008.json) binds commands,
logs, final native executables, client source, packaged models and the following
owning evidence. All completed commands exit zero with their original gates.

| Check | Local result |
|---|---|
| Locked workspace tests | 1,867 passed, zero failed, three existing ignored |
| Unfiltered coverage, original 90 percent floor | 93.34 percent of 75,743 lines; 5,048 missed |
| Formatting and strict all-target workspace lints | Passed |
| Workspace release and standalone server release | Passed |
| Deterministic CPU benchmark, 16 participants, 1,200 ticks, seed 42 | Check and original assertions passed on the final native executable |
| Dependency licenses, bans, sources and advisories | Passed; existing warnings retained |
| Whole-client gate on Godot 4.7.2-stable | 336 scripts and 155 harnesses passed |
| Client-check wrapper verifier | All ten success/failure scenarios passed |
| Controlled live-character renderer checks | 77 controls plus overview on each of OpenGL and Vulkan, with weighted motion and retained visible-pitch negative controls |
| Ordinary M09 and M10 crew routes | 27 and 28 states passed, including exact accepted Tern feet and correct moving/stationary gait |
| Refreshed standard gameplay and menu tour | 32 states passed; all original stills and three effects strips inspected; fourteen stills copied unchanged into the local gallery |
| Frozen loopback network matrix | Eight exact CI cases, seven exact roster rows and a 120-second native soak passed |
| Windows release export and actual exported install check | All three live bodies/support curves loaded; TDM and 5v5 Sabotage wire readiness and owned Stop passed |

The final server SHA-256 is
`149b6711eb120fea228c6b4bd39f2d19657cae00095dd9fa60a310b6b2ddaf61`;
the playtest harness is
`35d386017ea10cc96acc8aeb6a3dd9d11d159bacaa9cffa9f98551378531bf82`.
The standard-tour wrapper's normal release build was a no-op and retained that
server hash. Raw root logs are under `.agents/live-buildout-20261008/`.
The exported game is at `.agents/live-buildout-20261008/package/fragr.exe`,
beside its matching server. This resource/install smoke is not a completed
release ZIP, legal-notice packaging gate, signing or other-desktop execution.

The [character fixture receipt](live-character-fixtures-20261008.md) records
weighted geometry, both renderer paths, first-person hiding and carried-profile
corrections. The [crew receipt](live-crew-routes-20261008.md) identifies actual
visible Tern frames separately from off-camera samples, the original M10 ammo
failure and exact diagnostic facts. The QA correction distinguishes total pools
from ready magazines and changes only two M10 expectations. It landed during
the whole-client gate after initial parsing; focused regression, a final parse,
the complete M10 replay and fresh standard tour all exercise the final checker.
No player, supply, combat, route or timing rule changed for that correction.

The [network receipt](live-buildout-network-20261008.md) binds frozen copied
binaries and all sixteen checks. Separate CTF route proof resolves a take and
capture. The fresh contested case has twelve frags, zero takes/captures and a
time-limit ending, within unchanged assertions. Its pass does not establish a
contested capture. The two-minute rotating soak has no queue overflow or
degraded state; loopback results establish neither physical LAN nor capacity.
The [gallery receipt](../screenshots/readme-20261008.json) preserves all earlier
successful and failed capture hashes. Its current record is an incomplete
Arena Duel observation, with zero kills, one death and fourteen seconds alive.

Other desktop execution, hosted CI, publication, fresh human play and physical
LAN retain their existing acceptance gates. Existing unrelated dirty work was
preserved; infrastructure drafts were not validated or applied by this pass.

## Spend and remaining acceptance

$0 new cash, zero paid image/model/audio calls and no top-up or overage. The
existing models and committed sounds were sufficient. Nick's $4.65 image-balance
report remains a reported balance; this work does not establish a live reading.

Edda retains her recorded walking skin defects and Splice still needs mechanical
pivots. Remaining enemy bodies use directional baked art. Tern's dim optics,
original shoulder details, seated console contact and individual hand work
remain art gates. The campaign still has eleven connected prototypes; M12-M20
mission systems, the Walker, ending and fresh-player acceptance remain open.
Two-machine LAN, human multiplayer balance, larger populations and final art
retain their existing roadmap owners. All five external issues retain their
state pending their wider acceptance criteria. No commit, push, release, cloud
change or deployment belongs to this local increment.
