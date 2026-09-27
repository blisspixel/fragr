# M02 optional side ward

**Status:** in flight, 2026-09-27. This work follows the processing-floor
[gantry pass](m02-floor-gantry.md). It is one bounded part of the accepted
[Persons Unknown brief](../campaign/m02-persons-unknown.md), not completion of
the level or the later full maintenance loop.

## Goal and why

Give the processing floor one deliberate optional route with a visible captive
group and an independent guard encounter. The current route is linear and its
only other captive is the one Latch opens in the required ward scene. A player
should be able to choose the side ward, clear it, see the captives free
themselves, and still finish the main route without visiting it.

The side ward branches from the processing floor on its east machinery side.
Keep a clear grounded path around the gantry stairs and the dock approach.
Reserve the service edge for the accepted maintenance loop, which later
connects to the antechamber and gallery.
The prior north opening let a player reach the floor and side ward after the
ward guards fell but before releasing Latch. One visible ward-exit shutter now
opens from the existing release control. It keeps the reunion before the
optional captives and uses M02's already prepared gate worlds.
Do not open that full shortcut in this slice: an antechamber-to-floor entrance
upstream of the shutter would undermine the rescue order. Set the full loop
junction and timing in its own route pass.

## Boundaries

- Keep `ward_reached -> companion_released -> party_departed` as the required
  objective chain. The dock clear and departure cannot depend on the side ward
  or on Latch pathfinding.
- Keep one required Use control and one release-controlled exit shutter, with
  no extra player switch. Captives are agents held by
  the Union; they are not enemy bots, equipment rewards or a joke. Do not name
  them or settle their later fate here.
- Do not add the full floor roster, Notary combat, the gallery tableau, a new
  model API, or a paid asset call. A room preview must use existing authored
  surfaces and render seams.
- No new cloud resource or external charge. The $20 build allowance remains
  available; actual spend for this slice is $0.

## Architecture and contract

`server/maps/m02-persons-unknown.json` owns the solid opening, side-room
geometry, optional supply and guard group. The group must not be an `after`
dependency of the required floor or dock encounters. `server/src/encounters.rs`
already owns activation, completion and retry reset. Mission facts derive
from that state rather than a second mutable guard-clear flag.

The ward shutter closes the only route into the floor before release. It is
authored as M02 gate bit 0, triggered by `companion_released`, with matching
signals at the restraint frame and shutter. The closed and raised collision,
navigation and presentation worlds are prepared before readiness. On retry the
mask returns to zero; a late join receives the current raised world. The floor
guard trigger and entry recovery move to the new exit path. This door is the
accepted release action's visible result, not another puzzle step.

The server owns the side ward guard-clear fact as
`m02.side_ward_secured`, derived from the existing encounter state. Two
render-only captive figures respond to that validated fact, including on late
join and retry. It establishes that they can open their restraints and begin
leaving. It does not assert they reached an exit. Evacuation will need a
separate server fact once their route exists. The M02 wire, Rust and GDScript
validation, capability gate and `docs/protocol.md` change together. No
identity, address or secret data enters the fact.

Changing this authored map changes its content hash. Test that a durable M02
run with the old hash reports incompatibility and that the New Run archive path
remains usable. Preserve M01 run carry and the M02 development child.

## Build and verification

1. Record the current floor-to-dock route and map reachability. Close the old
   north opening and put one release-controlled exit shutter beside Latch.
   Prove the side ward and dock unreachable before release and reachable after.
   Add the east branch at ground level, away from the gantry stairs, with enough
   clearance for the live pawn, a safe return path and useful optional supply.
2. Add an independent, bounded side-ward guard group. Prove main-route clear
   and departure with the group untouched, and optional clear with the group
   defeated. A Continue restores guards and the room's initial state.
3. Add the guard-clear fact and visible captive self-release, with late
   observer reconstruction and retry reset. An actual evacuated state waits
   for a future actor route and its own server fact.
4. Run loaded-map support, navigation and live collision tests, then a
   first-person detour and a normal direct route with ordinary damage and
   ammunition on Standard and Severe. Inspect full-resolution frames and
   motion. Regenerate the tour for any changed player-facing surface.
5. Run the repository gates: Rust formatting, Clippy, tests, benchmark,
   unfiltered 90 percent coverage, release build, license checks, Godot
   checker, playtests, roster, soak and CI. Record command results and any
   unrun check instead of inferring a pass.

## Acceptance

- The optional room is visible as a branch, traversable without a jump, and
  worth visiting for its fight or supply. The player can leave it without a
  dead end or an ally collision.
- A player who skips the room can rescue Latch, clear the floor and depart;
  an optional clear has a distinct server-observable outcome.
- Captive self-release follows the server guard-clear fact, survives late
  join and resets on Continue. No client animation decides the outcome.
- Evacuation is not represented by this slice and cannot be inferred from
  guard defeat or a released animation.
- Story order, server authority, high coverage floor and the no-spend bound
  hold. Scripted clears are authoring evidence, not an unsteered player gate.

## Open review

The accepted brief describes a maintenance line from the antechamber to the
floor that also skips the stair's second landing, although the antechamber is
after that landing in the current route. The full loop needs a route sketch
and junction decision before its walls move. The release shutter is now the
common boundary: any future gallery-to-antechamber shortcut or maintenance
flank must rejoin on the ward side of that shutter, then reach the floor only
after Latch's release. The optional side ward can ship without deciding the
earlier shortcut. The Notary remains an unreachable, noncombat
M02 sighting and first fights in level 4; the older
[`flying-drones.md`](flying-drones.md) mission numbers need correction when its
plan is next edited.

## Rendered review

The 2026-09-27 Standard detour tour completed all 24 states and departed with
ordinary damage and pickups. These inspected first-person frames show the
same ward exit before and after Latch's release, then the optional room before
and after its separate guard encounter:

- [Exit shutter held](../screenshots/m02_ward_exit_held.png): the dark panel
  closes the only ward-to-floor opening while Latch remains restrained.
- [Exit shutter raised](../screenshots/m02_ward_exit_open.png): the same
  opening reveals the floor after the existing release action.
- [Held side ward](../screenshots/m02_side_ward_held.png): two restrained
  captives are visible past the short entry baffle.
- [After guard clear](../screenshots/m02_side_ward_free.png): the doors have
  opened and both captives have stepped clear. Latch is the pale figure at
  right. This shows release presentation, not evacuation.

The room remains graybox art. A scripted clear with ordinary combat proves the
route and state contract, not fresh-player readability or final balance. The full
maintenance loop, separate evacuated fact and unsteered review remain open.

## Verification and handoff

- The optional Standard first-person manifest completed 24 of 24 states,
  including both shutter states, the side guard clear, captive release and dock
  departure. The
  regular tour completed 32 of 32 states and published the current screenshot
  set. The separate 17-state Latch motion tour passed on the new map, including
  its sampled companion route. All three used the pinned Godot 4.7.2-stable
  binary. The frames above were inspected at full resolution.
- A seeded Severe route test departed alive after all 18 authored enemies
  were defeated with ordinary pickups. Focused server map, route, wire and
  child-process tests passed. The old M02 content-hash test confirms that New
  Run archives the prior document bytes without treating them as corruption.
- `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets
  --locked -- -D warnings`, `cargo test --workspace --locked`, and
  `cargo llvm-cov --workspace --locked --fail-under-lines 90` passed. Coverage
  was 93.79 percent of unfiltered workspace lines. `tools/godot_check.sh`,
  `tools/test_godot_check.sh`, `cargo deny check licenses bans sources`, and
  `git diff --check` passed. CI will rerun whole-workspace gates on the draft.
- The release workspace build and deterministic 16-bot benchmark passed. Four
  named mixed-agent playtests passed. The six-map 2/6/6/8/12/16 roster script
  passed. A 120-second rotating-map soak held 20 Hz, with 0.51 ms lifetime
  p99 tick time and 38.8 MiB maximum RSS on the local Windows run. These arena
  results do not prove M02 balance or cloud capacity.
- Remaining review gate: PR CI. Fresh-player navigation, visual readability
  and side-fight balance still need human observation. The side ward is
  optional; it does not finish the maintenance loop or M02.
- External spend was $0 for this slice. No cloud resource was applied.
