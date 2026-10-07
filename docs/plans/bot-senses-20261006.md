# Rule bot senses and finite arcade equipment

Status: **in flight**, 2026-10-06. Local implementation and verification are in
progress. Parent: [server excellence](server-excellence.md).

## Goal

Make free-for-all, team deathmatch and Conquest rule bots observe a fight before
they react. Give those bots the same finite spawn bag, magazines and reload
durations as a joined human. Preserve distinct movement personalities and the
shared authoritative damage and navigation paths.

## Design and scope

`server/src/sim/bot_senses.rs` owns each pawn's last observed hostile pose,
reaction deadline, staggered observation clock and deterministic angular error.
Observation runs every two ticks, staggered by seeded identity. It requires a
view cone and a clear ray through authoritative geometry. After losing sight,
the bot may search the last observed location for a bounded interval. It never
updates that location from an unseen target. A current visibility veto can stop
a shot between observations without revealing a new target pose to its aim.

The existing session controller pass updates observations before movement.
Movement and bounded route following remain at 20 Hz. The four-search-per-tick
navigation budget stays unchanged. Empty memory routes to available supplies or
known map spawn locations so bots explore rather than follow unseen opponents.

Full-arsenal arcade rule bots in these modes arm the existing inventory magazines, request
the existing timed reload when empty, switch to a supplied gun when a pool is
exhausted, and seek weapon pads when dry. Death uses the existing spawn refill.
Weapon-only rules retain unlimited reserves with their existing magazine reload.
Leaving these modes through the playlist disarms rule-bot magazines while
preserving the carried total, so CTF and Sabotage controllers keep their
single-count equipment contract. A dry bot seeks ammunition before optional
health or armor. Golden Rail pursuit and its weapon selection remain intact.

## Boundaries

No new dependencies, paid services, wire fields or protocol version. External
agents retain their existing single ammunition count and do not gain an MCP
reload command. Campaign, the episode-zero boss, CTF and Sabotage controllers
are outside this perception slice. Their current contracts remain separate;
this work does not claim ammunition parity for every controller in every mode.
Difficulty selection, hearing, tactical team quotas and large-population claims
are later work. This is not a human fun acceptance.

Conquest shares observed aim, reaction, turn speed, noise and magazines while
retaining its capture-point destinations. Navigation to a noncombat objective
continues to suppress firing; a bot holding a point can engage an observed
opponent. Hidden enemy motion cannot redirect the capture destination.

## Verification before acceptance

- Seeded target tests prove view-cone rejection, authoritative wall occlusion,
  delayed first fire, repeatable bounded aim error, frozen last-known positions,
  expiry, reacquisition and death/reset behavior.
- Session tests prove the navigation pass cannot bypass the sight/reaction gate,
  finite rounds run out, reload consumes the existing duration, a dry bot seeks
  supply, and respawn restores the ordinary bag. Agent and campaign inventories
  retain their established behavior.
- Run focused Rust tests, the complete server tests and formatting/lint checks.
  Record actual commands and failures here. Run the seeded 8- and 16-bot release
  benchmarks and a server smoke when the shared build queue is available.
- Report baseline and changed measurement evidence separately. No capacity or
  hardware claim follows from a functional test.

## Spend and success

All work is local, with $0 service charges. Acceptance requires the above tests
and honest measured evidence, plus readable review of the final diff. Unsteered
TDM, five-seat Sabotage and the two-computer LAN trial remain open human gates.

## Local evidence and integration handoff

The initial eleven focused cases pass through
`cargo test --locked -p fragr-server --lib bot_senses` (11 passed, 2026-10-06).
They include actual Session firing after reaction, actual pickup restocking,
the finite 80/24/16 spawn bag, exact existing reload times, owner reset, CTF
transition, and both observation phases across seeded groups of 8 and 16.
The first Session fixture started on the opposite observation phase and its
patrol turned before first sight; the corrected fixture deliberately enters on
the observer phase. The separate stagger fixture retains both phases.

The existing broad `bot` filter also matched `both` and the long CTF seed survey.
It exposed an ordinary-combat interaction before that survey finished: the
unchanged Compliance boss fired three times but was killed without a hit on
Arena Duel, seed 67. The existing roster assertion remains unchanged. The first
angular-error bound of 0.025 radians was revised to 0.055 radians. Arena Duel
and Compliance Yard then passed the unchanged roster gate, but the Compliance
boss missed all four shots before dying on Directive 17. The arcade boss now
uses the same observation/reaction/aim seam while retaining its existing HP,
gun and ammunition contract. Episode zero remains excluded. It avoids supply
pads and preserves its precise long-lane role with one quarter of the ordinary
aim-error bound. Before that final precision factor, the exact roster check
still failed on Directive 17 (six boss shots and zero hits), while every ordinary
personality moved, fired and hit. The final precision change and the six-map
roster gate need the parent's next composed native check. No assertion was
removed or reduced. The broad run was stopped after
that failure and is not a passing suite. A later compile briefly hit the
concurrent vehicle module's incomplete constructors, recorded separately.

The immutable test executable built from the 0.055-radian source and shared
arcade-boss senses passed all eleven focused cases again. That executable
predates the final boss precision factor, which is not claimed tested here.

The retained pre-change executable has SHA-256
`2fe89df62ef6ee41c0627c994eb6fca46c6fe4b9e5ebff5748df96f9bd93d751`.
Its build time predates HEAD, so these are a retained-binary comparison, not an
exact-source baseline. Both runs use Arena Duel, seed 42, 1,200 ticks, release
profile on Windows x86_64 with 16 available logical processors. The harness
includes session work and JSON encoding, with zero network clients. The
16-bot run also spawned the existing Compliance boss.

| Retained binary | Mean tick ms | p99 tick ms | Over 50 ms | Repeated trace |
|---|---:|---:|---:|---|
| 8 bots | 0.0823 | 0.3768 | 0 | identical |
| 16 bots | 0.1644 | 0.8192 | 0 | identical |

Commands were `fragr-server --bench 8 --bench-ticks 1200 --bench-check
--bench-assert --seed 42` and the same command with `--bench 16`. Receipts are
under `.agents/bot-senses/`. A fresh composed release measurement, full server
suite, lint, broader workspace checks and human acceptance remain open.

The composed October 6 source subsequently passed all twelve focused senses
tests, including Conquest delayed fire and cover rejection, and the unchanged
`every_existing_bot_behavior_moves_and_fights_across_the_roster` gate across
all seven maps. The final quarter-error Compliance precision is included in
that passing run. Its Directive 17 result is nine shots and four hits;
Holdfast Atoll is eleven shots and six hits. Full workspace checking and
warning-denying all-target Clippy passed before the final Conquest helper
extraction; the final composed release and lint receipts are tracked with the
island integration evidence. These results do not close human acceptance.
