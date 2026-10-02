# Solid living character bodies

**Status:** implemented, 2026-10-01. Local gates passed; CI and release pending.
Explicitly requested after first-person
play showed walking through other characters. Sequencing remains in the
[roadmap](../ROADMAP.md#full-build-order-2026-09-27). **Spend:** $0.

## Problem and ownership

Previously, live movement integrated against authoritative map solids and bounds,
but other living participant and campaign bodies did not block ordinary walking.
Server-owned contact resolution now handles those bodies, with matching bounded
contact math in local presentation prediction. Visual sprite size or a client-only physics
body cannot establish a server collision rule.

Client integration and the shared plan accompany a small
movement contact module, simulation integration and deterministic behavior tests.
Keep collision radii and registered actor heights in existing authoritative
constants. Do not reinterpret faction, callsign or control role as solidity.

## Required behavior

Living active participants, enemies and companions block walking when their
horizontal bodies and vertical spans overlap. Corpses, eliminated or inactive
bodies do not trap movement. Preserve map support, stairs, jump clearance and
moving-tram support. Contacts must slide rather than push a body through a wall,
and pre-existing overlap must permit escape. No standing on characters or new
actor physics is implied. Bound pair work for the current supported roster and
keep deterministic processing and actual movement velocities.

Do not break the Crawler's existing swept leap-contact damage, supported Notary
hover/wreck lifecycle, party readiness or companion following. Any dynamic
contact policy must be tested against real simultaneous movement and actor
height differences rather than only endpoint circles.

Local prediction uses recent validated snapshot bodies and the same contact
math without deciding positions or outcomes. Bound retention and reset on map,
role, disconnect and actor removal. Authoritative acknowledgements remain the
reconciliation source. No second networking channel or duplicated wire schema.

The compatible optional snapshot Boolean `collidable` exposes exact server
eligibility, including detached bodies that remain visible. Missing values retain
legacy true semantics; present nonbooleans are rejected. Reachable M02-M05
civilians use their mission feet and matching deterministic keys only during
active play. M02 publishes actual feet every active tick so the mirror does not
use its former four-tick observation cadence. No faction or control-role rule
decides solidity.

Eight projection passes are followed by at most one conservative fallback pass
per body. A 32-body queue exposed penetration with only eight fallback passes;
the corrected bound stops unresolved local movers while a distant mover retains
its proposed state. Current bounded roster behavior is tested separately from
any future large-roster performance claim.

## Focused evidence, 2026-10-01

Seven Rust contact tests pass, including an actual GameState tick and accepted
ACK velocity, detached and dead eligibility, tram refusal, support recomputation,
height differences, a crowded queue and an unrelated mover. Shared contact
vectors match the client. The new client contact harness passes those vectors,
sustained glancing progress, the 32-body queue, stair/wall support, exact civilian
keys, actor heights and malformed snapshot failure paths. The existing movement
goldens still pass all 37 cases and 1330 states after adding the explicit-height
integration entry point. These focused receipts are under
`.agents/m06-buildout-20261001/`; these focused checks preceded the final
integration and first-person evidence below.

The complete client checker now passes all 184 scripts and 86 harnesses, with
clean logs and each harness's own PASS marker. A subsequent narrow predictor
guard preserves exact kernel velocity when nearby bodies leave the endpoint
unchanged; its focused prediction, contact, movement-golden and manager checks
also pass. The matching server guard passes the original bit-exact ACK test
without changing its assertion.

The first full Rust pass exposed controller and fixed-route civilian regressions
that the small contact cases could not prove: occupied paths, shared workshop
endpoints and projected feet outside strict polylines. The original CTF seed
survey passes again at 15/16 completed rounds and 16/16 visible combat drops,
retaining its 14/16 and 8/16 floors. Workshop berths remain on their authored
routes inside actual boarding, with solids intact. Final full Rust and ordinary
campaign gates remained pending those owning fixes at this stage; the final
receipts below close them rather than substituting the earlier client PASS.

An actual first-person integration diagnostic now passes through the ordinary
server and human GameManager input path. A second living synthetic participant
stays stationary while held forward input records 19 applied, positive-speed
ACKs with zero accepted horizontal velocity, 19 consecutive stopped snapshots,
minimum centre separation 1.0 metre, and exactly zero measured camera and
predicted-position drift. Ordinary sidestep and forward input then pass the peer
without a position override. The initial controls card is dismissed with normal
Enter input before captures. The stopped still, six-frame motion strip and
passed lookback were inspected. This uses the earlier contact binary and is
explicitly diagnostic; the final matching-release rerun is still required.
Receipt: `.agents/m06-buildout-20261001/contact-pov-diagnostic-visible/`.

M03, M04 and M05 fixed-route civilians now refuse lateral or backward contact
projections rather than publish feet outside their strict routes. Four focused
actual-session regressions pass through unchanged MissionClient validation,
including ordinary player blocking and walking clear. The M05 proof checks
900 ticks, grounded motion, worker spacing, actual on-route boarding and 40
settled ticks. Geometry, route tolerances and departure gates remain unchanged.

### Current-source workspace and CPU gate

The final frozen source passes formatting, warning-denied workspace Clippy,
1240 passing workspace tests with zero failures and three existing ignored tests,
the full release build, and license, ban and source checks. Receipts are
`wrap-fmt.log`, `wrap-clippy.log`, `wrap-workspace-tests.log`,
`wrap-release-build.log` and `wrap-deny.log` in the same diagnostic directory.

| Windows x86_64 release CPU sample | Fighters | Ticks / seed | Tick p50 ms | Tick p99 ms | Maximum ms | Ticks over 50 ms | Determinism |
|---|---|---|---|---|---|---|---|
| Arena Duel, 16 bots, 16 available threads | 17 | 1200 / 42 | 0.245759 | 1.572863 | 2.2498 | 0 | pass |

The quiet-host benchmark includes session work and encoding. Its matching
release binary has SHA256
`BCDA020E4CC79FE4A4068982387ECBAE9CFD982EE406E1307A2C78C062B17311`;
receipt: `contact-playtest-final/bench16.log`. Congested avoidance can forecast
eight ordinary intents for six ticks using nearby bodies. This sample proves
the measured roster and budget, not crowded 64-player scale or GPU performance.
Final unfiltered workspace line coverage passes at 94.27 percent (51231 lines,
2933 missed). All 14 matching-release benchmark, mode, CTF, mixed-roster and
soak checks pass with unchanged binary hashes; the parent mission plan records
the measurement tables and shared-host limits. Matching-release rendered
evidence is recorded below. The final clean campaign and published-tour
receipts are recorded in the closeout below.

The final matching-release first-person check now passes with clean exit and
logs. Its unchanged release hash is the one recorded above. Held ordinary
forward input again produced 19 applied positive-speed ACKs with zero accepted
horizontal velocity, 19 consecutive stopped observations, minimum separation
1.0 metre and exactly zero camera or predicted-position drift. Ordinary
sidestep/pass input succeeded. Both owned processes exited. The stopped view,
six-frame strip and passed lookback were independently inspected and archived
as `docs/screenshots/actor_contact_stopped.png`,
`actor_contact_stop_strip.png` and `actor_contact_passed.png`.
Receipt: `contact-pov-release-final/`. This is a two-participant static-room
diagnostic on Windows Compatibility with an AMD Radeon 780M, separate from
campaign, remote-network and wider hardware acceptance.

### Final local closeout

The final current-source client checker passes all 184 scripts and 86 harnesses
with clean exit 0 in `client-whole-contact-final.log`. The ordinary-input M06
tour in `.agents/qa/m06-port-contact-second-final/` passes all 25 states and all
21 named guards, real marker and departure. Its corrected inner gallery route
skirts a living dormant Turret instead of entering that body's collision volume;
the regression reproduces refusal of the former endpoint. No collision rule or
waypoint tolerance is weakened. The final record retains zero deaths, zero HP
loss, 45 armor loss and one secret claim across three visited locations.
The standard tour in `.agents/qa/m06-standard-contact-final/` passes 32 states
and publishes 13 inspected stills. Both tours exit cleanly without the prior
shutdown texture errors, and all owned server and renderer processes close.

Container build/runtime, legal notices and `health.status: ok` probes also pass
with an unprivileged, read-only, no-new-privileges process and completed cleanup.
These local gates complete this increment; CI and release remain pending.
Current fault-verifier completion is root-owned. Human feel, fresh-player and
difficulty acceptance, wider network conditions and broader hardware remain open.

## Verification and acceptance

Require deterministic stop, slide, mutual approach, overlap escape, dead/inactive
body, vertical separation, static wall and stair/tram cases. Shared Rust and
GDScript vectors must verify contact math at the owning boundary. Exercise
prediction resets and real authoritative movement, then run complete Rust/client
checks and coverage. Inspect an ordinary-input first-person approach to a living
character and the final campaign route before claiming the collision works.
Record navigation regressions and player/agent/spectator behavior honestly.
