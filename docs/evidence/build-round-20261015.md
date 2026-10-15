# Walker, Sabotage and weapon handling composition

Status: local verification in progress, 2026-10-15. Baseline: `902ec8f`,
v0.83.0. The [bounded round](../plans/build-round-20261015.md) owns scope.

## Actual changes

The isolated Continuance Walker range adds strict authored machinery, five
translated body solids, three stations, warned stomp and artillery attacks,
finite shell stock and open recovery joints. Server capability 48 is required
where the machinery is registered. M13 retains floor 47, campaign rules 4 and
save version 17. M14 remains unavailable as a connected mission.

The client reads the same accepted body and projectile facts. It presents a
mechanical silhouette, locked attack marks, recovery shutters and an integrity
readout. Both walking and vehicle prediction update the translated collision
and suspend speculation during relocation. The separate Sabotage change lets
rule bots recover or defuse around idle participants while retaining active
defuse ownership. Rocket reload movement follows the actual private deadline.

## Encounter and rendered evidence

Native ordinary routes clear with both Agent and negotiated Human equipment.
The human uses actual magazines and eight reload requests. Neither route
changes phases, health, position or resources directly. The separate controlled
plate and obstruction tests remain fixtures and are not represented as played
clears.

The ordinary three-state OpenGL route in
`.agents/round-20261015/walker-live-3/` completes with 100 HP, 146 Bullets and
10 Rockets remaining. It observes seven reload deadlines, traveling artillery,
relocation, recovery and disable. Inspected stills show the real locked marks,
raised recovery shutters and disabled machinery. Capture uses Godot 4.7.2,
Xvfb and Mesa llvmpipe, not a hardware performance test.

After the loading recovery fix, the complete isolated Vulkan Forward+ route
also passes with clean exit and logs. It retains 100 HP, 141 Bullets and ten
Rockets, and observes eight reload deadlines across 21 captured frames.
The [bound receipt](walker-rendered-20261015.json) records the actual source and
binary hashes. Inspected [artillery](../screenshots/walker-foundation-20261015/locked-artillery.png),
[recovery](../screenshots/walker-foundation-20261015/open-joints.png) and
[disable](../screenshots/walker-foundation-20261015/disabled.png) stills show the
final concise integrity readout. This run explicitly uses the software Vulkan
driver and an owned Xvfb display. Earlier fallback and blocked-input runs remain
failed evidence, not hardware acceptance.

The [Rocket handling route](../../client/qa/rocket-reload-motion.json) walks M13
to its actual finite claim, returns to cover, fires and reloads. The inspected
eight-frame strip in `.agents/rocket-20261015/office-reload/` contains four reload
frames and the returned held pose. The server accepts R at tick 2703 and refills
the tube at 2719; the total remains eleven Rockets throughout that reload.

The complete standard tour captures 32 states and publishes fourteen inspected
stills. Its [receipt](../screenshots/tour-20261015-build-round.json) records the
software renderer and recovery of the publication footer after a concurrent
shell-file edit interrupted the wrapper. The actual capture and logs pass;
no failed image or failed effect probe was silently accepted.

## Failures retained and corrected

- Actual native boxes omit `bottom` at zero. Client fixtures now include the
  serialized map, so its default height and numeric-index behavior are tested.
- JSON numeric indices left the original static solids visible beside the
  moving machine. Rendering tests now prove that only the registered body is
  hidden and ordinary cover remains.
- Shared explosion validation rejected the real seven-metre stomp. Full native
  stomp and shell snapshots now cross the same strict effects boundary. Review
  also found that existing five-metre vehicle blasts were refused; their actual
  native radius and damage are now admitted without changing combat.
- The first free-straying capture route fired Rockets into nearby cover and
  died from splash. The passing route uses the authored open flank and changes
  weapons with the recovery window. The failed run remains in
  `.agents/round-20261015/walker-live-2/`.
- Independent review corrected direct Rocket damage from nearby ground grazes,
  committed shots from dead shooters, multi-participant activation, stale map
  binding and artillery warnings disappearing before committed impacts.
- Golden comparison initially exposed a last-bit floating-point change when
  reparsing expanded decimals. The gate now compares the exact emitted bytes
  as well as retaining typed semantic checks, without a tolerance.
- An initial handshake timeout could leave a failed loading card blocking a
  subsequent successful human join. A before/after regression now proves that
  changing role starts a fresh world gate, rejects stale snapshots and releases
  controls only after the new map, snapshot and ordinary controls-card timeout.

## Remaining gates and limits

The complete Godot checker passes 371 scripts and 176 harnesses. Subsequent
focused Walker, loading recovery and real desktop-host tests pass on the final
source. The locked workspace release build passes. All required live network
scenarios, seven-map roster and 120-second soak pass; the
[network receipt](network-round-20261015.md) retains the contested CTF timeout
without a capture and observed roster spawn deaths. The soak maintains 20 Hz,
with no budget overruns or queue overflow. Unfiltered locked workspace tests
pass with 2,074 tests and five intentional ignores. The final local run bounds
test threads to two, matching the coverage run, after an earlier high-concurrency
run exceeded existing readiness deadlines. No timeout or assertion was relaxed.
Formatting, warning-denying workspace Clippy and dependency license/source
checks pass. The deterministic 16-bot, 1,200-tick CPU benchmark passes its
unchanged assertions (p99 0.819 ms, maximum 2.123 ms). Unfiltered workspace
coverage passes at 92.97% of lines (79,298 of 85,290), above the unchanged
90% gate. Regions measure 92.50% and functions 91.03%. GitHub integration and
packages are tracked in [PR #403](https://github.com/blisspixel/fragr/pull/403).
No new cash or funded-credit generation was used.

This is a boss foundation and handling increment. Staged support, the optional
jeep fight, fallen-world transition, coalition departure and durable level 14
promotion belong to the [next integration](../plans/m14-launch-authority-integration-20261015.md).
Fresh-player understanding, difficulty balance, polished gait, final art,
physical LAN and full-campaign enjoyment remain unproven.
