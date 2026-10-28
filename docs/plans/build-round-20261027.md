# Build round, 2026-10-27

Goal: carry the roadmap's remaining Episode V rung and the open #431, #432 and #434 scope forward in waves. Each wave lands as one reviewed PR from an integration branch and returns to one green `main`. Lanes push temporary `waveNN/<lane>` branches, never open their own PRs, and are deleted when absorbed.

Non-goals: new modes, new services, transport rewrites, cloud apply, save migrations. Spend stays inside the asset-credit authorization in `AGENTS.md`.

## Nick's decisions (2026-10-27)

- Larak Lot Rocket supply (#432): weapons drop on death. A fragged fighter's held gun becomes a short-lived pickup. A second launcher pad was not chosen.
- Host announcer (#431): Callum records the voiced Host calls now, before the ElevenLabs reset on 2026-11-06. A later recast re-records the same slots.
- Meshy credits (reset 2026-11-03): final Inheritance Paver and Surveyor models for Levels 19 and 20, replacing the placeholders.
- Waves of three or four lanes.
- Episode V evidence: agent-led acceptance and independent agent review are the default; no human reviewer is required to proceed. Platform, device and human gaps are recorded, not simulated.

## Wave 11 (shipped, #490)

| Lane | Scope | Owner doc |
|---|---|---|
| `m19-market` | Finish the #487 market diagnosis (the overlapping-strip case) without buffs; then, if the boundary is trustworthy, extend the earned M19 survey to the next authored objective toward the water tanks | [L19 brief](../campaign/l19-planned-works.md), [harness guide](../../tools/playtest/README.md) |
| `carry-bridge` | Join #483's earned M01 departure and disk-save retry to a bounded M02 window under the constrained policy | [harness guide](../../tools/playtest/README.md) |
| `inheritance-models` | Lore-gated Meshy Paver and Surveyor, integrated and inspected in Levels 19 and 20 | [asset practices](asset-practices/README.md) |
| `mp-rules` | Weapons drop on death with a measured Rocket share, Duel queue and winner-stays, host presets and mutator stacking, the Conquest ticket bleed | [multiplayer excellence](multiplayer-excellence-20261017.md), [bot and enemy AI](bot-and-enemy-ai-excellence-20261017.md) |

## Wave 12 (shipped, #495)

Host voice (Callum), the hit confirm and the Scatter pass; Rocket use, CTF pads and side calls for rule bots; campaign guard sighting, squad roles and barks; the #434 stage 1 baseline with stage 3 measured and deferred. The main hotfix #496 rests dropped guns where a body can stand (roster stall on map 6). Follow-ups: #489, #491, #492, #493, #494, #497.

## Wave 13 (planned)

The Recall Notice deliberate-profile regression and M14 seed 1015 (#493); the slow-reader close (#492); #434 stage 4 (acknowledged deltas and compact encoding) and bounded lag compensation; the roster deck pockets (#491), test flakes (#494), the seed 44 stranded case (#497) and the fixed-seed Continue replay (#489); then raising levels 1 to 18 to the golden-slice bar in rendered passes.

## Verification

Each wave PR carries the AGENTS.md verification list run on the final tree, inspected captures for anything a player sees, and exact-head and exact-main CI. Headless checks, inspected visuals, measurements, fresh-player acceptance and installed releases stay distinct.
