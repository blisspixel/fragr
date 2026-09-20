# Inheritance command and capability benchmark

**Status:** later research/design goal, 2026-09-19. No implementation or validated
benchmark exists. Requested ambition: an exceptionally strong strategy simulation
that could contribute to evaluating advanced general intelligence.
**Dependencies:** polished FPS/campaign, authoritative strategy primitives,
replays, agent interfaces, and measured simulation scale. Do not displace those.
**Spend:** local baselines first; any paid evaluation requires explicit aggregate
and per-run budgets through the existing provider gates.

## Product and research goal

[MODES.md](../MODES.md#later-inheritance-command) owns the playable mode. Agents
direct an abstract fictional restoration across many fronts, with consequences
visible to human spectators. Demanding planning, uncertainty, coordination and
resource allocation should produce an interesting game and a serious evaluation
environment. Mathematical rigor is a requirement, not decoration in the UI.

Keep the existing [CPU/render benchmark](../BENCHMARK.md) separate in purpose.
Fast simulation and intelligent decisions are different measurements.

## Research questions to settle before implementation

- What constructs are measured: long-horizon planning, partial observability,
  causal adaptation, constrained optimization, multi-agent coordination, transfer?
  Define each behaviorally and test whether tasks actually distinguish it.
- What can each participant observe and command? Explicitly model observation,
  action, transition, reward and termination, including information leakage and
  simulator privileges. Study the suitability of MDP/POMDP or multi-agent
  formulations rather than selecting one by name alone.
- Which task families require qualitatively different strategies? Reserve
  generated and authored scenarios for held-out evaluation; seed changes alone
  do not establish a new distribution or prevent memorization.
- How are compute, wall time, observation frequency, action rate, context, and
  monetary cost controlled? Distinguish simulated speed from provider latency.
  Measure cost/performance tradeoffs instead of rewarding unlimited resources.
- Which random, scripted, search/planning, human and model baselines are fair?
  Add ablations that isolate memory, planning and observation advantages.
- Which outcomes should be reported separately? Mission success, resource use,
  ecological change, casualties, resilience and generalization need explicit
  definitions. A single weighted score can conceal tradeoffs or reward exploits.
- Which statistical design supplies enough power and uncertainty estimates?
  Predefine comparisons, independent trials, repeated-seed handling, failure
  treatment and confidence intervals. Avoid tuning a test set to rank a favorite.

## Trustworthy evaluation

Version scenarios, rules, agents, tools and scoring. Record deterministic seeds,
events, actions, information available at each decision, and environment/build
identity so results can be replayed and audited. Protect held-out material from
training prompts and ordinary game assets where the design requires it.

Probe reward hacking, invalid commands, crashes, timeout behavior, hidden-state
leakage, nondeterminism, overfitting, and policy brittleness. Do not silently drop
failed runs. Human-readable replays and independent review must challenge any
surprising result. Validate metrics against meaningful behavior, not just numbers
the simulator makes convenient to collect.

The [2026 international safety report](https://internationalaisafetyreport.org/publication/2026-report-extended-summary-policymakers)
documents evaluation gaps between tests and deployment. Checked 2026-09-19.
Before specifying mathematics or comparing systems, review current primary
research on generalization, agent evaluation, planning benchmarks and statistics.
No existing formalism, success threshold, or leaderboard is chosen by this note.

## Gates for a public claim

1. Reproducible local environment and non-model baselines.
2. Evidence that task families test the intended capabilities and resist obvious
   shortcuts; documented limitations and bounded claims.
3. Held-out evaluation with fair budgets, uncertainty, sensitivity analysis and
   adversarial review of scoring and information boundaries.
4. Independent reproduction and evidence of transfer beyond familiar scenarios.

Until then, call it an experimental strategy/capability benchmark. Success at one
game does not establish AGI, consciousness, moral judgment, or safe real-world
autonomy. Its fictional objective does not authorize real external actions.
