# Sector 9 spawn-exit evidence

Status: implemented, integration pending, October 15. Broad integration rejected the second candidate;
the corrected third candidate passes scoped native, live and rendered checks,
with final composed native verification passing. This receipt belongs to
[the bounded exit-cover plan](../plans/sector9-spawn-exits-20261015.md).
Live observations, deterministic reconstructed lanes and rendered/player review
have different scopes. No human enjoyment or physical LAN claim follows here.

## Baseline and first candidate

The preceding round's eight-client Sector 9 observation recorded six early
deaths among 37 frags. Every retained victim had moved from its spawn point.
The initial regression reconstructed all six death-time firing lanes and found
them exposed. These positions are not the missing full input replay.

The fresh release baseline and first candidate each ran five observations:

```text
fragr-playtest --map 4 --agents 8 --seed SEED --tiers reflex,planner
  --rounds 1 --frag-limit 8 --time-limit-seconds 60 --max-seconds 75
  --assert --report REPORT.json
```

All ten observations passed the existing assertions, with zero opening deaths.
The first candidate nevertheless did not satisfy the intended measured
improvement. Its north/south dividers and diagonal staging stacks screened the
six reconstructed lanes, while the live samples exposed side-hall gaps.

| Seed | Baseline frags | Baseline early deaths | First candidate frags | First candidate early deaths |
|---:|---:|---:|---:|---:|
| 40 | 36 | 1 | 31 | 0 |
| 41 | 34 | 0 | 30 | 0 |
| 42 | 34 | 0 | 35 | 1 |
| 43 | 30 | 1 | 28 | 1 |
| 44 | 34 | 0 | 35 | 2 |
| Total | 168 | 2 | 159 | 4 |

The pooled early-death fractions were 1.19% and 2.52%. These small, asynchronous
samples do not establish a statistically reliable regression or improvement.
They do reject using the original six-death sample as the sole comparison or
claiming success from reconstructed lanes alone. Baseline runs lasted 61.90 to
61.95 seconds; first-candidate runs lasted 61.90 seconds. First contact remained
about 6.35 seconds; the first candidate's longest no-frag gap was 8.20 seconds.
Maximum measured stuck duration was 0.55 seconds in both batches.

## Revised comparison

The second candidate extends the same dividers to the east/west cardinal bays,
lengthens two existing freight rows and adds paired inspection staging beside
the decks without crossing their stairs. Only Sector 9 geometry changes. It adds
twelve solids and reshapes two existing stacks; global pockets, spawn ranking,
shields, scoring and weapon damage are unchanged.

Four new side-hall lanes from the first candidate join the original six native
fixtures. Tests reject covering the recorded victim's standing space, exercise
actual unshielded Rail shots, walk both interior and service approaches from all
sixteen bays, and drive a north-bay runner under fire. That runner survives its
first forty ticks behind geometry and takes damage after leaving its cover;
no shield or altered damage rule supplies the protection.

The old geometry fails both the visibility fixture and the resolved-shot
fixture. Earlier route-fixture failures used an existing wall as a destination
and retained a high spawn's floor height after its downward exit. Those fixture
goals now follow the middle aisle and use actual destination support; no product
collision or route assertion was relaxed. The moving fixture initially stopped
one tick before the next Rail shot after clearing the oblique lane; the retained
trace shows the preceding shot hitting the divider. Its final five-second
window proves resumed damage after the unchanged first-two-second check.

The revised candidate repeated the same five commands, with every assertion
passing:

| Seed | Revised frags | Early deaths | Opening deaths | Match seconds | First frag seconds | Maximum stuck seconds |
|---:|---:|---:|---:|---:|---:|---:|
| 40 | 23 | 1 | 0 | 41.15 | 5.65 | 0.35 |
| 41 | 34 | 0 | 0 | 61.95 | 6.40 | 0.45 |
| 42 | 23 | 0 | 0 | 41.20 | 6.55 | 0.55 |
| 43 | 30 | 0 | 0 | 47.25 | 5.70 | 0.55 |
| 44 | 33 | 0 | 0 | 61.95 | 6.60 | 0.55 |
| Total | 143 | 1 | 0 | 253.50 | | |

The pooled early-death fraction is 0.70%, compared with baseline 1.19% and
first-candidate 2.52%. Three revised rounds reached the frag target before the
clock expired, so raw frag totals have unequal exposure. Pooled throughput is
33.85 frags/minute, compared with baseline 32.55 and first-candidate 30.82.
The revised longest no-frag gap is 6.60 seconds, and maximum measured stuck
duration remains 0.55 seconds. This supports keeping the bounded revision for
integration and rendered review. One versus two early deaths is too little
evidence for a statistically reliable improvement claim, and the remaining
early death is retained.

The remaining early death is seed 40, 25 ticks after respawn: the victim moved
from `(25.926817, 48.505672)` to `(27.77657, 44.312134)` while the shooter stood
at `(40.876575, 2.0798347)`. That middle-hall oblique exit is still contested.
The revision screens the retained ten lanes, not every possible firing lane.

## Targeted verification

The second isolated revision passed:

- All nineteen filtered spawn tests, including the existing arrival-order
  permutations, ten reconstructed lanes, resolved unshielded shots, thirty-two
  ordinary bay-exit routes and the moving runner's return to combat.
- Every map's native validation and the validated maps' flag-base walking test.
- A four-rule-bot scored CTF round on seed 42.
- Server Clippy with all targets and warnings denied, locked dependencies, and
  Rust 1.97.1; isolated workspace formatting and the owned diff whitespace check.
- The live `--ctf-route-smoke`: one take and one capture in 60.90 seconds.
- The eight-client Sector 9 team match (seed 42, sixteen-frag target,
  sixty-second clock): 27 frags in 61.95 seconds, first contact at 8.30 seconds,
  zero early/opening deaths and zero team kills, with four fighters per side.
- The existing four-client contested CTF check (one-capture target,
  180-second clock): all assertions pass, thirteen frags, zero early/opening
  deaths and zero team kills. It still ends 0-0 at 181.95 seconds, with one take,
  one combat drop, one return and no capture. The carrier progresses from
  137.73 m to 85.07 m from home over 11.40 seconds, with zero own-flag-away or
  home-blocked ticks. This is retained evidence of unresolved contested CTF
  scoring quality, not a successful scored match or a demonstrated route stall.

These scoped checks passed, but broad verification subsequently rejected the
geometry as described below. The controlled capture
and scored rule-bot round do not replace the contested observation, whose timeout
remains visible. Global CTF rules and controller policy were not changed here.

## Independent rendered traversal

Two seven-state ordinary-human routes passed with clean logs and 100 HP using
the exact preserved second-candidate server. Inspection covered east/west inner
exits and deck ascents, north/south loading aisles, and inner/rear service exits.
The paired staging leaves the stair approaches distinct; no new blocked passage
or floating cover was found. Broad neutral/red panels remain repetitive, an
existing environment-art limitation.

This is bot-free geometry practice with the documented `--no-round-events`
option, no teleports, resource grants or world edits. The renderer was OpenGL
Compatibility on isolated X11 with Mesa llvmpipe software, not physical GPU
performance evidence. The client was `fd8c527` at gameplay 48 to match the
isolated server. The current composed gameplay-49 client remains part of parent
integration.

The receipt `render-review.json` and both `art-*-practice/` directories retain
the source/binary bindings and captures. Earlier failed manual routes remain:
one deck approach hit a pre-existing diagonal bay wall, a stair-edge descent
stopped, and an observation without `--no-round-events` was killed by the timed
Compliance Drone. The final return walks off the outside deck edge, so this
review claims stair ascent but not stair descent. Incorrect harness configuration,
capability mismatch, an import-process crash followed by a successful unchanged
retry, and deliberately interrupted attempts are also listed in that receipt.

## Broad-gate failure and correction

The composed workspace run rejected the second candidate: 1,455 server tests
passed, two failed and four remained intentionally ignored. Existing Sabotage
checks found that the lengthened west row reached z=28, overlapping B's plant
area at `(-37.46967, 27.53033)` and the holding spot `(-38, 33)`. Attack, defense
and inter-site timing observations passed before the blocked hold route failed.
The earlier focused spawn, CTF and team checks did not cover that shared-mode
contract. Their passing results and all renderer captures remain retained, but
they do not establish acceptance of the second candidate.

The third candidate shortens both extended rows from sixteen to ten metres,
preserving their original rear edges and moving the inward edges from z=28 to
z=34 (and the origin-opposite pair). The twelve added solids remain unchanged.
Existing Sabotage assertions and spawn protections are unchanged. All four
spawn-exit regressions and all fifty filtered Sabotage tests pass, including
both original broad-suite failures. The complete nineteen-test spawn filter,
every-map validation, validated flag-base walking and four-rule-bot scored CTF
round also pass on the corrected composed source. Revised rendered inspection
passes; broad integration remains pending. The original full-gate failure and focused
correction logs are retained under `.agents/launch-authority-20261015/`.

The third candidate repeated all five commands with the existing assertions
passing:

| Seed | Frags | Early deaths | Opening deaths | Match seconds | First frag seconds | Maximum stuck seconds |
|---:|---:|---:|---:|---:|---:|---:|
| 40 | 31 | 1 | 0 | 61.90 | 5.65 | 0.45 |
| 41 | 31 | 0 | 0 | 52.40 | 5.65 | 0.50 |
| 42 | 29 | 0 | 0 | 61.90 | 6.65 | 0.45 |
| 43 | 32 | 0 | 0 | 61.10 | 6.00 | 0.45 |
| 44 | 25 | 0 | 0 | 51.20 | 5.65 | 0.40 |
| Total | 148 | 1 | 0 | 288.50 | | |

The pooled early-death fraction is 0.68%, against baseline 1.19%. Throughput is
30.78 frags/minute against baseline 32.55, a 5.45% reduction in this sample.
The longest no-frag gap is 6.65 seconds and maximum stuck duration is 0.50
seconds. The narrower rows preserve prompt contact and routes, but this sample
does not prove an overall fun improvement or statistically reliable reduction
in early deaths. Its remaining early death is seed 40: the victim moves from
`(53.94319, -10.729963)` to `(44.8553, -8.750492)` over forty ticks, while the
shooter is at `(28.997297, 2.4615264)`. That exit remains contestable.

These directional observations overlap a separate software-rendered campaign
review. Read-only `/status` requests sample each owned embedded server about
every ten seconds: all 32 responses are healthy, with zero recorded budget
overruns. The minimum mature tick rate is 19.9977 Hz, highest sampled window
p99 is 2.23 ms and highest observed lifetime maximum is 8.90 ms. These samples
document the overlap's live health, not an isolated CPU benchmark or a claim
about unobserved intervals after the final sample. Required benchmark and soak
remain separate gates.

The corrected candidate's controlled live CTF route passes. Its composed
four-client contested check also passes the existing combat/replication
assertions, but still ends 0-0 at 181.95 seconds: fifteen frags, two takes, one
combat drop and one return. The first carrier moves from 137.73 m to 86.07 m
from home over 224 observed ticks before death. The second moves from 139.51 m
to 44.56 m over 391 ticks until the clock ends. Both have zero own-flag-away and
home-blocked ticks. These are progressing returns, not evidence of a blocked
flag route. Contested conversion remains unresolved, as scoped separately in
[the carrier-contact follow-on](../plans/ctf-carrier-contact-20261015.md).

The corrected eight-client Sector 9 TDM comparison passes: 22 frags in 61.95
seconds, first contact at 8.80 seconds, zero early/opening deaths and zero team
kills, with four fighters per side. The composed eight-case network suite also
passes, including actual Sabotage plant/defuse route and contested Sabotage.
Its contested Sabotage observation records a plant and an elimination ending,
two frags and four pickups in 26.60 seconds. It does not establish every
Sabotage ending or human match balance.

Parent integration independently inspects six ordinary-human states on the
preserved third-candidate server using the current gameplay-49 client:
east loading exit, revised east row, its inner clearance, west loading exit,
revised west row and the ordinary walk from `(-38, 33)` to `(-38, 27)`.
All six pass with clean logs and 100 HP under `art-candidate3/`. Parent review
inspects the contact sheet and full-size east/west clearance stills, finding no
new clipping or floating geometry. This is geometry-only FFA practice, not a
rendered plant or defuse. This refreshes acceptance of the changed row ends;
the earlier cardinal/deck captures apply only to geometry unchanged between
the candidates. Bot-free practice, software rendering and no grants/teleports
retain the same scope limits as the earlier inspection.

The next full native run passes all 1,457 server unit tests with four deliberate
ignores, including the formerly failing Sabotage checks. It subsequently finds
four stale current-output assertions in `server/tests/local_child.rs`: the
writer correctly emits save version 18 while those assertions expect 17.
Historical v3-v6 input fixtures remain unchanged. The first failing full run is
retained; all eighteen focused process tests and the subsequent complete
workspace rerun pass with the corrected output expectations. This is
separate from the resolved geometry regression. The final composed workspace
passes 2,100 tests with five intentional ignores, strict Clippy, release build,
dependency policy and unfiltered coverage at 93.01% lines after the final MCP
Rocket selector correction. The seven-map roster,
isolated benchmark and 120-second soak also pass; their exact scope and binary
bindings are in [the composed native receipt](native-launch-authority-20261015.md).

## Source and retained artifacts

The unchanged Sector 9 baseline is from `fd8c527`, the Walker foundation merge.
Concurrent M14 protocol work temporarily made the shared checkout uncompilable,
so the first two candidates used a detached `fd8c527` checkout plus the owned
Sector 9 geometry and tests, with isolated build output. No unrelated files
were changed in that checkout. The third candidate uses the composed working
tree, including M14 and gameplay 49. Its preserved binary hashes, source hashes
and shared diff identify that boundary; embedded historical build-label strings
do not establish the actual source revision of these dirty-tree builds.

Logs, complete reports, candidate patches and private binaries are under
`.agents/sector9-spawn-exits-20261015/`. `before/` is the baseline; `after/` is the
retained first candidate; `after-v2/` is the rejected second comparison;
`after-v3/` retains the corrected comparison and live status samples. Nothing is
discarded when a seed is unfavorable. Live socket timing and random participant
identities make these repeated observations, not exact seeded replays.

SHA-256 bindings:

- Baseline playtest: `7bc159cca0360d0688e9098785eeebd75f02acc1a5250d694633571c5db11392`.
- First candidate playtest: `ed1a4bcff271a81140d5f16878c0e13414c422049c584698b2be19b3eabe42ca`.
- Second candidate playtest: `acee43d776da5c02d94a617b62214ed03e7bf82443d62845d339367c57af323c`.
- Second candidate server: `3affd0528ba26b5c70872bdf3044edbe5260b663717e0fc2201c9451fc89243e`.
- Third candidate playtest: `0256d895764d6586a05b32195beaef0ea215767457e12684d2a66fdd7577fa44`.
- Third candidate server: `f988abd4be6d1603120d4a7f7b7b48d7218dc131a53b3200df3b9e8dfdf4fef5`.

External spend is $0. Existing materials and the ordinary freight-interchange
identity are retained. No paid production, cloud operation or new public mode
is part of this work.
