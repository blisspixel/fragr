# M01 weapon discovery

Status: **implemented and locally verified**, 2026-09-19.
[Task #178](https://github.com/blisspixel/fragr/issues/178) records integration and release status.
Baseline: v0.23.0, `a110081`, all five integration CI jobs passed. Prior turn
completed and released the authored blockout; this increment changes gameplay.

## Outcome and boundaries

Enter M01 with fists, find Tack in confiscation, acquire Flechette before the
balcony fight, and manage ammunition with readable reload and dry-trigger
feedback. Humans and agents use the same authority and actions. Build the full
discovery loop, including presentation and live-map proof, before calling it done.

Enemy encounters, objective interaction, extraction, checkpoints and other
weapons follow. Latch is located here and rescued in M02. Do not add early
Inheritance contact. Connection role is control, not fictional embodiment or
agency. Existing arcade maps keep an explicit full-arsenal policy until their
economy is migrated with their controllers and measured balance.

## State and ordering

- One inventory model owns weapons, magazines, pooled reserves and reload state.
  Player owns the selected weapon; do not duplicate that selection in the model.
  Existing weapon damage and ray resolution remain shared across both policies.
- Fists are unlimited: 20 damage, eight-tick cadence, 1.8 metre reach. Tack has
  20 damage, five-tick cadence, 12-round magazine and 18-tick reload. Flechette
  retains its current shot behavior with 30 rounds and a 22-tick reload.
  Balance remains in `WEAPONS.md`; record measured adjustments there.
- A new gun grants a full magazine and the documented initial reserve. Reserves
  are shared by ammunition pool. Loading moves rounds from reserve; switching
  or death cancels an incomplete reload without losing rounds. Completing a
  reload before processing this tick's input permits firing on its completion
  tick. A new reload request suppresses firing until completion.
- Weapon selection rejects unowned guns. A newly found gun equips once; repeat
  ammunition collection does not force a switch. Dry fire never automatically
  changes weapons, consumes ammunition or starts a shot cooldown. Successful
  misses consume rounds. Cooldown, death and reload reject shots before any RNG
  draw or ammunition change. Held dry triggers produce bounded feedback.
- Reload is a discrete input, preserved across newer input frames until one
  server tick consumes it. R and gamepad X reload; C cycles radio stations.
- During this development slice, death restarts that participant at entry with
  fists and clears their introductory claims. Reconnecting is a new participant,
  not checkpoint resume. No inventory drops or transfers exist to farm. Future
  checkpoint restore must restore saved inventory and claims instead of applying
  this development reset to every mission boundary.

## Supply and wire seams

Extend the bounded authored-map schema with an explicit equipment policy and
validated supplies. Use existing `ArenaPickup` collision and claim processing.
Personal weapon supplies can be claimed once per participant life and never
remove another participant's introductory gun. Contested ammunition has one
winner per availability cycle. Reject unknown fields, unsupported grants, invalid
amounts, duplicate identifiers and unreachable placements before hosting.

Publish loadout changes only to the owning participant using `Recipient::Player`.
Represent reload completion by authoritative tick, so a countdown does not require
full inventory broadcasts every tick. Include personal claim IDs so local pickup
visibility agrees with the authority. Public snapshots retain held weapons and
world supplies without exposing every opponent's ammunition.

Add a gameplay capability separate from geometry version. Discovery servers
reject incompatible humans, agents and spectators before admission. Arcade
traffic retains legacy defaults and does not gain loadout messages. Update all
wire consumers, including MCP, scripted and decision clients, playtest controllers
and Godot. Validate received state before replacing the last valid observation.

The shared controller helper should select owned usable weapons, reload an empty
magazine with reserve, and seek a useful supply before fighting with fists.
Do not build separate inventory arithmetic into each agent. MCP remains slow
control, with the same ordinary action input as humans.

## Presentation

Distinct fists and Tack viewmodels, held sprites, pickups and short effects must
be inspectable alongside Flechette. Fists produce no gun flash or long tracer.
Show magazine/reserve, reload progress and a restrained dry indication in the
existing pixel HUD. Keep weapon bottoms anchored through walking and reload.
Inspect first-person, eye spectator and third-person motion.

Use existing local assets first. Any generation follows the canonical generators,
current quota verification, explicit caps and receipts. No top-ups or paid calls
in runtime or tests. No engine, dependency or transport migration is needed.

## Research and proof

Checked 2026-09-19: [Serde field attributes](https://serde.rs/field-attrs.html)
support defaulted, omitted legacy additions; strict nested authoring records
remain separate from compatibility wire records. Godot's stable
[gamepad button API](https://docs.godotengine.org/en/stable/classes/class_inputeventjoypadbutton.html)
uses button identity and pressed state; deprecated pressure is not a control.
Verify new input bindings with the installed 4.7.2 client harness.

Prove inventory conservation, exact reload boundaries and cancellation, rejected
selection/fire, finite reach and cover, death/reset, two simultaneous claimants,
independent introductory grants and late joins. Socket and MCP tests cover
capability rejection, private delivery and real actions. Run the full Rust and
Godot checks from `AGENTS.md`; do not lower coverage or loosen roster gates.

Walk M01 live through both routes, exercise each discovery, fire through one
magazine, reload, dry fire and switch. Inspect current OpenGL/Vulkan captures and
motion. Refresh the release tour and six-map mixed-client roster. Compare complete
CPU traces against v0.23.0 and explain any change. Record actual discovery and
reload timings; this still cannot establish a finished 10-15 minute mission.

## Evidence and continuation

Implementation and local verification are complete for the bounded discovery
loop. GitHub integration checks and release records establish shipped status.

- Rust: 641 tests pass, two existing ignored tests; strict Clippy and formatting
  pass. Unfiltered workspace line coverage is 95.62 percent. Workspace release
  build and dependency license, ban and source checks pass.
- Godot: all scripts parse and 19 headless harnesses pass. The checker itself
  rejects failed exits, logged errors and missing PASS markers. New checks cover
  foreign/stale/malformed private state, owned cycling, short reload taps, input
  binding conflicts, ammo UI, anchored wrists and alternating punches.
- Actual socket tests exercise human and agent movement, private initial state,
  discovery, one shot and exact-tick reload completion; spectators receive no
  loadout. MCP validates the same state and exposes it through observation.
- Two external clients, one scripted and one local decision controller, played
  M01 for 25 seconds. Both claimed Tack (1.53 and 2.09 seconds after joining),
  collected ammo and fought through deaths and fresh entry. Five frags occurred;
  the decision client sent 500 actions, observed 500 snapshots, made zero remote
  decisions and spent zero dollars. This is shared combat proof, not co-op.
- Live human discovery captures verify 12/36 Tack, 0/36 after firing, 12/24 after
  reload; Flechette 30/90, 0/90, 30/60 after reload, then 30/90 after collecting
  balcony Darts. The 18- and 22-tick completion rules are deterministic tests;
  inspected strips show lowering, progress, completion and restored counts.
- OpenGL and Vulkan each passed the ten-state M01 discovery tour at 1280x720 on
  Windows with AMD 780M. The 21-state release tour refreshed nine public stills.
  Review corrected a misplaced oversized Tack flash and weak punch extension.
  A same-tick pickup regression now ensures body and first-person feedback use
  the resolved shot, never the newly selected gun. The final 21-state OpenGL
  release tour and ten-state Vulkan discovery tour pass after that correction;
  both contact sheets and transient weapon strips were inspected.
- Final entry-view inspection found a client join race: an open socket allowed
  default aim to overwrite the authored spawn before the first snapshot. Input
  now waits for the current session's camera target. The regression failed before
  the fix and passes afterwards, including reconnect and preservation of local
  aim on later snapshots. OpenGL and Vulkan discovery tours now assert and show
  the intended facing toward confiscation. Reload and short-jump input fixtures
  establish the same bound-session precondition; their original assertions remain.
- Integration follow-up, 2026-09-20: [merged Windows run](https://github.com/blisspixel/fragr/actions/runs/35496071339)
  exposed an older MCP traversal test indexing player zero in a valid pre-join
  empty snapshot. The corrected test waits for the welcomed UUID, preserves
  map/floor assertions, and requires two metres of actual travel from its observed
  start rather than a world threshold another spawn could already satisfy.
  Workspace tests, strict Clippy, formatting and 32 repeated live traversal runs
  pass locally. This changes test synchronization, not runtime behavior. Release
  remains gated on successful integration checks for the correction.

### Arcade regression and CPU evidence

Mixed reflex/planner network clients passed all six existing roster gates without
changing thresholds. These runs still expose spawn deaths worth improving; passing
the gate does not establish finished multiplayer balance.

| Map | Clients | Seed | Frags | First frag, seconds | Spawn deaths |
|---|---:|---:|---:|---:|---:|
| Arena Duel | 2 | 67 | 6 | 10.35 | 0 |
| Compliance Yard | 6 | 42 | 29 | 6.25 | 0 |
| Directive 17 Substation | 6 | 19 | 22 | 2.95 | 4 |
| Sector 9 Transit Hall | 8 | 42 | 35 | 2.95 | 5 |
| Reclamation Gulch | 12 | 42 | 56 | 2.95 | 5 |
| Tripoint Works | 16 | 42 | 61 | 2.95 | 6 |

Release CPU runs: 12,000 ticks, seed 42, repeated complete traces, default budget
assertions. The map is part of the configuration and must match the baseline.
An initial 64-fighter comparison accidentally used map 1 instead of map 5; that
hash difference was a mismatched experiment, not evidence of a simulation change.
All three correctly configured traces exactly match v0.23.0.

| Fighters | Map | Mean step, ms | p99 step, ms | Maximum, ms |
|---:|---:|---:|---:|---:|
| 16 | 1 | 0.094 | 0.590 | 2.047 |
| 64 | 5 | 0.316 | 1.442 | 3.334 |
| 128 | 6 | 0.942 | 4.063 | 9.986 |

These are CPU session-and-encoding measurements, not network capacity or GPU
certification. Reports: `.agents/bench/discovery-{16,64,128}.json`. Network logs
and reports: `.agents/playtest/roster/`; validation receipts use
`.agents/discovery-*`. The plan retains the durable findings; local receipts are
disposable. Benchmark commands use `--bench N --bench-ticks 12000 --map M --seed
42 --bench-check --bench-assert`, with N/M from the table.

### Remaining work

M01 still has no authored enemies, objectives, extraction, checkpoints or opening
scene. The room kit is a readable blockout, not finished environmental art.
Tack's small world icon is an existing placeholder; fists and guns animate single
poses rather than a finished frame set. Dedicated Tack, melee, reload and dry
sounds remain in the separate audio refresh. Staged sidearm/swing candidates
failed quality screening and were not promoted. No generation credits were spent.

Next: build the intake encounter from the M01 brief with distinct Union human
and bot behavior, readable windups, animated silhouettes and encounter pacing.
Then add authored interaction, extraction and checkpoint state. Neither a fast
route nor several connected players proves a complete mission or working co-op.
