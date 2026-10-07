# Immediate local fire feedback

Status: **in flight**, 2026-10-06. Part of the current small-match fight pass
in [server excellence](server-excellence.md).

## Goal

An eligible local trigger plays the existing muzzle, weapon motion and sound
without waiting for a server shot. Server evidence continues to own traces,
impacts, ammunition, damage and hit markers. A confirmation must not replay
the predicted effect. Spectators continue to present resolved shots.

## Design and boundaries

Add one client presentation helper behind GameManager's existing action sender.
It tracks a bounded set of successful action sends, local fire cadence and
private inventory reservations. Use the existing server cooldowns at 20 Hz,
including the Repeater warmup. A weapon switch cannot erase cooldown. An empty
magazine, a known reload, blocked controls, death or unavailable connection
must prevent a speculative shot. Reset at connection, map, role and life
boundaries. Rejected predictions cancel any remaining effect; sound already
played cannot be taken back.

Reconcile through the existing ordered shot results, loadouts and input ACKs.
No protocol, server authority, weapon balance, public settings, dependencies
or asset changes are planned. Keep stale or ambiguous evidence conservative
and bound the outstanding window. Do not infer hits from input.

## Verification and acceptance

- Focused deterministic client checks cover first-click timing, automatic
  cadence, weapon switching, empty/reloading inventories, rejection and
  confirmation, late evidence, lifecycle resets and Repeater warmup.
- Exercise GameManager's actual sending and resolved-shot seams with probes,
  proving one predicted effect plus one authoritative marker, with spectator
  behavior retained.
- Run clean headless import, parsing and the relevant harnesses, followed by
  the full checker. Inspect a rendered fire sequence and refresh the required
  visual tour with automated mouse capture disabled.
- Record commands and their results here. Passing fixture checks do not prove
  a two-machine latency or fresh-player feel gate.

## Spend

Local checks and existing assets only, $0. No external asset calls.

## Evidence

Implemented locally in `local_fire_feedback.gd`, GameManager's successful
action-send path and the existing HUD/pawn effects. Sub-frame trigger taps
remain latched until a successful send. One global cooldown survives weapon
switches. The eight presentation intervals are checked against the Rust
definition by the new harness. Speculation stops when a receipt waits more
than 500 ms, with at most eight outstanding receipts. Acknowledged inputs
without corresponding shot evidence retire after two world ticks; confirmed
ammunition stays reserved until the matching loadout arrives.

Local checks on 2026-10-06, Godot 4.7.2-stable:

- `--headless --path client --script res://scripts/test_local_fire_feedback.gd`:
  PASS, including actual successful/failed action sends, held fire, sub-frame
  trigger taps, inventory gates, switches, Repeater warmup, late confirmation,
  rejection, sequence wrap, a death trade and spectator effects.
- Existing `test_input_pacing.gd` and `test_shot_effects.gd`: PASS with clean
  error logs. Headless import and direct parser checks passed.
- `--path client --rendering-method gl_compatibility --script
  res://scripts/test_local_fire_feedback.gd`: exit 0, PASS, clean error log on
  AMD Radeon 780M. Four inspected frames under
  `.agents/local-fire-rendered/` show idle, the input-frame muzzle flash,
  the settled weapon before server evidence, and the authoritative hit marker
  after a held-back confirmation. The gun does not replay on confirmation.
  The flash capture freezes only presentation time during image encoding;
  the confirmation wait runs in real time. Automation asserts that it never
  captures the desktop pointer. This fixture is not a network latency test.
- `git diff --check` passed for the touched existing scripts.

The first complete client checker was stopped during parsing when the disk
filled. Its partial log and the original zero-byte captures are not passing
evidence. After generated build cleanup, all four images were regenerated
successfully. The complete checker and published tour still await the composed
server build. Two-machine latency, listening and fresh-player acceptance
remain open. No paid calls were made.
