# Player records, statistics and commentary

Status: local service-record slice implemented and locally verified,
[#199](https://github.com/blisspixel/fragr/issues/199), updated 2026-09-20. CPU benchmark and
trace recording already shipped in #166; their implemented contract lives in
[BENCHMARK.md](../BENCHMARK.md). This plan supersedes its earlier benchmark wish
list. Spend: $0, local computation and offline localized copy.

## Product contract

Give players a persistent service record, a campaign run history and multiplayer
match reports. Keep the default result screen short, chunky and readable; an
optional analysis view supplies the mathematics. The tone can roast a meat proxy
or an agent for what actually happened, with a separate commentary toggle. This
is part of the game's personality, not a claim to assess someone's intelligence.

| Surface | Planned facts |
|---|---|
| Local profile | Completed/failed/abandoned runs, matches, time played, kills, deaths, weapon counts and earned titles/cosmetics. Separate campaign and multiplayer totals. |
| Campaign run | Mission and difficulty, rules revision, attempts, continues spent, active time, deaths, damage, weapon use, objective completion and authored rescues/secrets when those systems exist. Show total effort separately from the successful attempt. |
| Multiplayer match | Map, mode, roster/control roles, result, frags/deaths, damage, shots, hits, streaks and objective contributions when the mode implements them. Show partial participation and disconnects. |
| Analysis | Per-weapon counts, rates with denominators, time distributions, comparable run history and a versioned local export. Performance diagnostics retain their own timing scope. |

A profile is a local record, not an authenticated public ranking. A callsign is a
display label, never identity. Human/agent control, body and faction are distinct.
Custom server results need an explicit trust label; no new account or matchmaking
service is required for this increment. No background telemetry or paid runtime
commentator.

## Current evidence and canonical seams

- `server/src/bench.rs` measures offline CPU session/encoding work and payload
  counts. `trace.rs` records and verifies seeded observations. These do not measure
  rendered frame time, socket delivery or authenticated player history.
- `tools/playtest` aggregates match evidence for engineering checks. Its report
  is not a persistent player profile or an authoritative reward ledger.
- `sim.rs` resolves shots, deaths, pickups and outcomes; `inventory.rs` owns
  ammunition and dry triggers. `mission/` owns run identity and retries. Collect
  facts at these decisions, not by guessing from HUD text or callsigns.
- `protocol.rs` and its child modules own shared wire types. The client validates
  external state at a single boundary before displaying or persisting it.
- `settings.gd` remains preferences only. Profile data uses a separate versioned
  document with recoverable replacement, corruption handling and an isolated test path.

## Implementation sequence

1. **Authoritative summaries.** Add a small shared counter/summary seam. Define
   one accepted-shot trial, actual HP/armor damage, kill credit and active tick
   duration. Assign session/match/run/attempt identity before counting. Test
   simultaneous trades, environmental deaths, duplicate observations, leave and
   retry. Reuse the same facts in human UI, MCP observations and exports.
2. **Campaign result and local history.** Persist terminal records once per run
   ID, retaining best completed attempt separately from all attempts. Repeated
   delivery cannot award another completion. A continue resets mission state,
   never lifetime effort. Leaving/crashing is not a win; incomplete observations
   remain explicitly incomplete. Wire schema and local save versions evolve
   independently. Saves do not silently refill continues.
3. **Multiplayer reports and profile.** Give rounds stable IDs, retain disconnected
   participants in the report and mark participation windows. Ratios derive from
   summed numerators/denominators, not averaged match percentages. Add a retro
   profile/results menu and a local export. Earned cosmetic rules belong in
   [difficulty-and-rewards.md](difficulty-and-rewards.md).
4. **Optional commentary and deeper analysis.** Select original localized lines
   from verified facts and rotate them without interrupting combat or story.
   Further statistical estimates need a declared question, sampling unit and
   uncertainty model. Ratings and public leaderboards stay deferred until their
   identity, trust and game-mode contracts exist.

Before each rung, bound its wire changes, persistence migration and acceptance
in this plan. Do not implement an analytics platform ahead of useful records.

### Active slice: local service record

Implement shared server counters for accepted attacks, damaging attacks, effective
HP/armor damage, kills, deaths and living active ticks. Keep per-weapon counts and
current-attempt counters alongside total mission effort. Count at resolution,
including simultaneous trades; intro, retry choice, death and terminal waiting
do not count as active play. Round boundaries reset round counters; a continue
resets only attempt counters. Administrative removal is not a death.

Deliver a versioned private record to each participant at bounded cadence and
on outcome changes, with session/player identity, map, scope and authoritative
status. MCP observation exposes that same record. Repeated observations replace
the current record instead of adding its totals again. A disconnected client can
retain its last observation as incomplete, never promote it to a win.

The client stores the latest 256 records in a versioned local history separate from settings,
validates files and messages, and exposes a retro service-record menu with
campaign and arena totals kept apart. History retention must be explicit; this
slice does not imply unlimited lifetime archives. Test replacement, duplicate
delivery, corruption, unsupported versions and failed writes. Local records are
unauthenticated and distinguish owned local play from external server claims.

The service-record menu has campaign, arena and practice tabs, per-weapon
numerators/denominators, latest-attempt versus total effort, participation windows
and a JSON export. The optional localized quips currently cover observed dry
triggers and completed melee-only attempts. No achievement awards, rating, public
leaderboard, campaign save/resume or paid commentary in this slice. No new
dependencies.

### Implemented storage and compatibility

`server/src/statistics.rs` updates counters on actual sim decisions;
`protocol/statistics.rs` owns the versioned private record. Gameplay capability 8
opts into delivery. Earlier clients receive their prior protocol; local launch
still requires a matching client/server pair. `player_record.gd` validates the
client boundary. `player_records.gd` owns persistence, and `records_panel.gd`
renders it with the existing menu theme and localization file.

The on-device profile identity is independent of callsign. A record key is
session UUID, player UUID and round. Mission run identity, difficulty, attempt
and allowance travel in its scope. A continue clears attempt counters only.
Counter snapshots replace the existing record, including repeat terminal delivery.
Disconnect/crash without a terminal report leaves an incomplete observation.
Deaths here are authoritative combat deaths, not administrative removals.

History writes on a new record, attempt/outcome changes, at most ten seconds of
ordinary updates, and scene exit. `user://service-record.0.json` and `.1.json`
alternate generations. A temporary write replaces the older slot; the other
slot remains the last committed copy. Load selects the newest validated slot.
Corrupt slots recover from the other valid generation; wholly corrupt or future
formats block writes and remain untouched. This is recoverable replacement,
not a claim of power-loss durability. The format is local and single-writer;
cloud synchronization and concurrent-writer reconciliation are not implemented.
The export preserves the same record fields. Totals cover retained records, not
an unlimited lifetime archive. Earlier records expire after the stated limit.

Primary sources checked 2026-09-20:
[FileAccess](https://docs.godotengine.org/en/stable/classes/class_fileaccess.html),
[DirAccess](https://docs.godotengine.org/en/stable/classes/class_diraccess.html),
[pinned Windows rename implementation](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/windows/dir_access_windows.cpp),
[pinned Unix rename implementation](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/unix/dir_access_unix.cpp),
and [Serde field attributes](https://serde.rs/field-attrs.html). Windows removes an
existing rename target before moving the source, which is why a single temporary
file and rename cannot substantiate an atomic-save claim on all target platforms.

## Count definitions and statistical discipline

- Keep attempts, encounters and matches distinguishable. Campaign kills across
  failed attempts are effort, not unique mission enemies defeated. A mission
  completion and a campaign completion are different outcomes.
- Accuracy means accepted damaging shots divided by accepted shots, with the
  exact numerator and denominator visible. Dry pulls are separate. Multi-pellet
  or piercing weapons must define shot and target counts separately before use.
  Zero trials means unavailable, never 0 percent or NaN.
- Record actual effective damage, with armor and HP separated if both are shown.
  Overkill is not effective damage. A trade preserves both resolved shots and
  credits one death once. Do not infer weapon from a later inventory snapshot.
- Active play ticks exclude intro, death choice and terminal waiting. Wall-clock
  session duration is a different measurement. Speed records carry map/content,
  difficulty and rules versions; incompatible routes are not one leaderboard.
- Descriptive distributions carry units, count and percentile method. Raw counts
  do not need artificial confidence intervals. For inference, state the model:
  shots in one engagement are correlated, and repeated seeds are not independent
  new players. Wilson intervals suit a declared binomial model, not every ratio.
- Prefer paired seeds/configurations and repeated match-level samples for balance
  comparisons. Show effect sizes and uncertainty; p-values are not probabilities
  that a balance claim is true. No arbitrary sample-size cutoff makes an estimate
  reliable, and weapon selection confounds kill share. Numbers guide review;
  they cannot mechanically establish fun or declare every map disparity a bug.

Primary statistical reference checked 2026-09-20:
[NIST guidance on proportion intervals](https://www.itl.nist.gov/div898/handbook/prc/section2/prc241.htm).
Research the relevant primary method again when implementing an estimator.

## Roasts that belong in this world

The first two lines are implemented; the continue line remains proposed:

- On an observed dry trigger: "Your ammunition request is pending review."
- After a completed melee-only attempt: "Zero ammunition. An accounting triumph."
- On the final remaining continue: "One appeal remains. Try surviving the hearing."

Each line has a specific fact predicate, localization key and repetition limit.
Narrative copy can be subjective; the supporting numbers cannot be invented.
Keep identity, sensitive traits and unseen player motives out of it. Let players
mute commentary independently. No radio dependency and no synthetic voice that
blocks play. Roast both free beings and the bureaucracy without replacing the
campaign's serious character moments.

## Acceptance

- Known event sequences yield exact counts, including retry, trade, exhaustion,
  incomplete match, leave and repeated terminal delivery.
- Save round trips, malformed/unsupported files, interrupted writes and migration
  failures preserve recoverable data and never grant duplicate rewards.
- UI, agent observation and export agree on the same record and denominator.
- Inspect rendered profiles/results and commentary in campaign and multiplayer;
  exercise more than one map, controller role and outcome.
- Full repository checks pass. Persistent stats, achievements and commentary stay
  labelled planned until these surfaces exist and have evidence.

## Verification (2026-09-20)

- Windows Rust 1.98.1: 733 workspace tests passed, two existing ignored tests;
  strict workspace Clippy passed. Unfiltered workspace line coverage is 95.60
  percent. An initial final coverage invocation stopped during compilation
  without a compiler diagnostic; the retained retry completed successfully.
- The shared JSON record fixture passes Rust, MCP and GDScript validation.
  Focused client checks prove replacement without double counting, corrupt-slot
  recovery, failed-write preservation, unsupported-format refusal, bounded
  retention and export agreement. Terminal results cannot rewrite attempt detail.
- All 30 client harnesses pass, including live local-launch, campaign recovery,
  player records and the quiet combat feed. All ten checker fault scenarios pass.
  Formatting, workspace release build and license/bans/source checks pass.
- The published 23-state tour and fourteen-state Standard M01 route pass on
  Windows, Godot 4.7.2, OpenGL compatibility and AMD Radeon 780M. Inspected menus,
  gameplay, effects and service records retain the retro presentation. The M01
  terminal record has twenty kills, no deaths, 138 attacks, 70 damaging attacks
  and 1400 effective HP damage; both its attempt and total agree.
- A completed arena round on Directive 17 Substation persists three deaths and
  1782 alive ticks for an idle human participant. Captured server totals, attempt
  and scope match the saved terminal entry exactly. This is participation, not
  a win or an aim-quality measurement. No attacks displays unavailable accuracy.
- Rendered recovery shows four deaths and three spent continues as one failed
  Severe run, with latest-attempt time separate from total effort. Early rendered
  shutdown reported retained OpenGL textures after its PASS marker. Reusing the
  tour's scene-retirement drain yields a clean rendered run. One headless run
  also reported retained resources; the focused retry and final complete checker
  are clean. No error log was accepted solely because its harness printed PASS.
- The four-agent live smoke passes with seven frags, first frag at 9.2 seconds
  and no spawn deaths. The full mixed-client roster passes on all six maps below.

| Map | Seed | Agents | Frags | First frag s | Longest gap s | Spawn deaths |
|---|---:|---:|---:|---:|---:|---:|
| Arena Duel | 67 | 2 | 5 | 10.35 | 12.70 | 0 |
| Compliance Yard | 42 | 6 | 30 | 5.10 | 6.00 | 0 |
| Directive 17 Substation | 19 | 6 | 24 | 2.95 | 6.30 | 2 |
| Map ID 4 | 42 | 8 | 34 | 3.70 | 5.00 | 3 |
| Map ID 5 | 42 | 12 | 52 | 2.95 | 4.20 | 4 |
| Map ID 6 | 42 | 16 | 63 | 3.25 | 4.05 | 1 |

These are bounded engineering checks, not final balance or proof of finished
maps. Spawn deaths remain in the evidence rather than being hidden by aggregates.
Current receipts: `.agents/stats-*-final.log`, `.agents/stats-coverage-retry.log`,
`.agents/stats-hud-godot-final.log`, `.agents/playtest/stats-roster/`,
`.agents/qa/stats-hud-{arena,m01,round}-20260920/` and
`.agents/stats-recovery-reviewed.log`. Integration remains tracked by #199.

CPU gate, Windows release, Ryzen 7 7840U, map 1, seed 42, 16 bots, 1200 ticks:

| Scope | p99 ms | Maximum ms | Ticks over 50 ms | Repeat hash |
|---|---:|---:|---:|---|
| Offline session plus encoding | 2.097 | 3.551 | 0 | Identical |

This is one local budget-gate observation. The shell verifier was also running.
The offline roster has no socket clients, so this is not a private-record delivery
throughput measurement, a speedup claim or a public-server capacity result.
