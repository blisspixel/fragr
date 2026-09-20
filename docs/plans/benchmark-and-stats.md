# Player records, statistics and commentary

Status: planned player-facing increment, [#199](https://github.com/blisspixel/fragr/issues/199),
updated 2026-09-20. CPU benchmark and
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
- `settings.gd` remains preferences only. Profile data needs a separate versioned
  document with atomic replacement, corruption handling and an isolated test path.

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

Examples are proposed copy, not implemented triggers:

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
