# Sabotage objective ownership

Status: **shipped**, 2026-10-15, through
[PR #403](https://github.com/blisspixel/fragr/pull/403) in v0.84.0.
Bounded multiplayer refinement under rung 1
of the [full build order](../ROADMAP.md#full-build-order).

## Goal and observed defect

The existing Sabotage controller elects the nearest living participant to recover
a loose charge or defuse a planted one. A closer idle human or external agent
therefore makes every rule bot decline the job. A teammate moving closer also
displaces an already working bot, losing earned defuse progress. Both conditions
can waste the round without a player understanding why their teammates stopped.

Elect one eligible registered rule bot for otherwise unclaimed objective work.
Retain any actual ongoing defuse, human, external agent or rule bot, until the
authoritative hold ends. A nearby participant is not a promise to perform work.
Keep existing combat interruptions, ordinary Use, charge touch, navigation and
round authority. Coalition and Union remain match sides; control role implies
neither allegiance nor character identity.

## Scope and architecture

Reuse `GameState.bots` for controller identity, shared actor eligibility for
living presence and `Sabotage.hold` for actual committed work. Selection remains
bounded by the admitted roster and uses a stable identity tie-break. No second
objective ledger, timer, input channel, protocol field, new mode or dependency.
This changes rule-bot decisions only. Human and external-agent interactions
continue through the existing authoritative resolution.

## Verification and success

First reproduce the incorrect decisions before changing production code. Test
Sector 9 and Low Water with mixed roles, ordinary held Use and actual sim ticks:
idle non-bots must not suppress recovery or defuse; an ongoing defuse must survive
a closer teammate; human and agent defusers retain their work; dead, detached,
waiting, spectator and wrong-side bodies cannot own a bot objective. Retain the
existing Sabotage tests and run the native bot survey when available. Composed
workspace gates belong to the integration owner. Human balance, physical LAN
and rendered readability remain separate acceptance evidence.

## Spend and research

All work is local, $0. No asset request, cloud operation or paid inference.
Primary-source research is recorded with the evidence; external examples inform
stable team work and bounded decisions, never borrowed content or a new stack.

## Local result

The [dated receipt](../evidence/sabotage-objective-ownership-20261015.md) records
four pre-fix regression failures, all 50 passing Sabotage tests, warning-denying
server Clippy and a four-seed, eight-bot native survey. All four matches finish,
with 24 rounds, 13 plants and four defuses. Both venues and mixed human/agent
rosters are exercised by the new deterministic tests. The survey covers Sector 9
only. Composed workspace CI, integration and human acceptance remain open.
