# Continuance Walker combat foundation

Status: **shipped**, 2026-10-15. Integration:
[PR #403](https://github.com/blisspixel/fragr/pull/403). This bounded foundation advances the next
campaign dependency in the Roadmap. It does not complete connected M14.

## Goal and scope

Build a distinct authored Union artillery machine, with three health stages,
committed visible attack warnings, traveling shells, exposed joint recovery,
bounded physical relocation, and ordinary finite infantry weapons as counters.
The first range isolates the boss so its timings and counterplay can be checked
before adding M14's later support squads. No ordinary enemy becomes a boss by
renaming it. The existing M14 battlefield, mission progression, saves and
coalition departure remain separate integration work.

## Architecture

`protocol/walker.rs` owns strict geometry and snapshot facts. `maps/authored/walker.rs`
validates registered torso and joint solids, three grounded stations, the
activation area and a conservative navigation sweep before readiness.
`sim/walker.rs` owns health, locked attacks, shell travel and relocation.
`current_arena()` translates the registered solids from accepted server feet.
Whole movement steps refuse bodies, vehicles or obstruction; characters are
never carried by the Walker. Shared encounter reset restores the machine and
clears committed shells. Existing resolved shot and blast seams own damage.
Capability 48 admits the new world and snapshot contract; no new MCP action,
combat authority, dependency or scripting runtime is introduced.

## Design and research

The accepted [M14 brief](../campaign/l14-launch-authority.md),
[enemy roster](../ENEMIES.md) and [Mars direction](../design/mars.md) govern this
work. The first phase teaches the machine alone; later mission support must
enter through visible lanes. Infantry has two supplied flanks and may finish
after losing or declining the jeep. Joint vents open in recovery so moving
toward a readable opening has a concrete reward.

Primary-source design review checked 2026-10-15:
[combat decision-making](https://www.gdcvault.com/play/1024940/Embracing-Push-Forward-)
supports distinct movement and weapon choices, rather than a stationary health
bar; [Valve's pacing presentation](https://steamcdn-a.akamaihd.net/apps/valve/2009/ai_systems_of_l4d_mike_booth.pdf)
supports explicitly separated pressure and recovery. These established sources
inform the design, not a claim of newly published research or copied mechanics.
No engine/API version changes are needed.

## Verification and acceptance

Deterministic tests must cover strict malformed authoring, actual finite shots,
plate versus open-joint damage, covered splash, locked aim, warning-before-harm,
traveling shell impact, refused relocation, finite stock, disable and reset.
The range must admit ordinary weapon routes on foot. Client facts need strict
validation and rendered telegraph/motion inspection. Accurate automation is
authoring evidence, not fresh-player difficulty acceptance. Whole workspace
checks, coverage and screenshot evidence are recorded after integration.

## Spend

$0. Existing materials, geometry and sounds only. Paid assets are neither
required nor authorized by this foundation plan.

## Native implementation evidence, 2026-10-15

The distinct machine and standalone `walker_foundation_development.json` range
are implemented. Registered five-part collision translates at the actual server
pose; the initial 900 HP, three truthful health bands, warnings, finite 36-shell
stock, physical shell travel, covered damage, bounded relocation and joint
recovery are exercised by native tests. The range does not yet add later-phase
support units or collapse the disabled machine into a fallen collision world.
Campaign rules remain 4 and saved runs remain version 17 with M14 pending.

`cargo +1.97.1 test -p fragr-server --lib --locked walker -- --nocapture` passes 14
tests with one ignored export helper. Final focused log:
`.agents/round-20261015/walker-source-final.log`.
The ordinary-input clear starts at the real spawn and walks to authored Rifle,
Rocket, west ammunition and rocket stocks before fighting from the flank.
It changes no pose, health, phase or inventory outside normal input and supply
resolution. Its two deterministic seed-1048 runs report:

| Participant | Clear | Final HP | Rifle ammunition | Rockets | Reload requests |
|---|---:|---:|---:|---:|---:|
| Agent, finite shared pools | 545 ticks (27.25 s) | 100 | 136 | 9 | 0 |
| Human, negotiated magazines | 547 ticks (27.35 s) | 100 | 145 | 10 | 8 |

These are accurate-input authoring tests, not fresh-player times or difficulty
acceptance. The separate damage-isolation test explicitly holds recovery and
grants its fixture stock; it is not counted as an ordinary route. Other tests
cover actual ballistic movement, locked targets, no warning-period harm, covered
stomp/splash, one blast per machine, whole-step obstruction and guaranteed
recovery, exhausted artillery, reset, strict malformed maps and the shared
native/client golden. The golden contains actual map and phase snapshots plus
eight malformed state cases, and its ordinary test compares regenerated bytes.
Actual full stomp and shell snapshots additionally retain the resolved victim
damage and environmental owner for the client blast boundary. The wire regression
compares exact serialized bytes before semantic decoding, avoiding a false
failure from the JSON parser's final-bit rounding of expanded float decimals.
An additional full snapshot records an unowned jeep's actual radius-5 explosion
after its forty-tick burn, covering the vehicle boundary needed by combined
arms. The range's Host line now truthfully describes an unfinished mission
slice rather than claiming no encounters exist.

Independent review identified and fixed three real issues: a nearby ground hit
could have acquired Rocket direct damage, a final accepted shot could have been
lost when its shooter died, and a nearer outside participant could have masked
someone inside the activation region. Regressions now exercise all three. The
physical Rocket sweep test records 43 splash damage for a near-leg floor graze
and 108 combined damage for a registered open-joint contact.
The strict loader also refuses static decorations hosted on registered moving
parts, preventing a light or sign from remaining behind during relocation.

The adapter's current-map validation and stale-observation invalidation were
also strengthened after review. All 110 adapter tests and all-target strict
Clippy pass in the reviewer's bounded check; logs are under
`.agents/sabotage-objective-ownership-20261015/walker-adapter-*`. Rendered
ordinary-input evidence and composed workspace checks are recorded by the
active build round before shipping. Final art, a fresh-player review, later
support-lane staging, connected M14 objectives and save promotion remain open.

The [composed receipt](../evidence/build-round-20261015.md) records ordinary
OpenGL and isolated Vulkan clears, each at 100 HP with finite stock remaining,
actual native explosion goldens, independent boundary and lifecycle review,
and the full client/network checks. Both renderer runs use software drivers;
they establish inspected presentation and input paths, not hardware frame rates.
