# M01 service cache and Shiv

Status: paused at an unshipped draft checkpoint, 2026-09-20.
Parent: v0.33.0, `47507db`. Spend: local code
and existing art first; no paid provider batch in this increment.

## Player outcome

Give Recall Notice its planned optional discovery beat: notice an altered service
panel near the maintenance route, use it to open a real cache, and recover a Shiv.
The blade is a finite-range, ammunition-free melee upgrade over fists. The main
route, guaranteed guns and Latch's transfer objective remain independent of it.
The cache belongs to people quietly resisting confiscation, not an early message
from the Inheritance. Do not announce the hidden room with a distant objective.

The player uses ordinary interaction at the panel. Opening exposes physical
space, with a locally readable cue and reward. A short corner notice confirms the
discovery without covering the crosshair. Retry closes the cache and restores its
reward alongside existing mission-entry restoration. Repeated use and concurrent
requests cannot duplicate it. Each participant can claim their discovered weapon.

## Architecture

- Extend authored mission preparation and `RuntimeMap`, preserving one collision
  and navigation representation. One optional cache plus the existing exit gate
  has four bounded, prevalidated geometry states; prepare them before readiness.
  Reuse gate and use-target validation, not a client-only door or tick-time bake.
- `mission.rs` owns proximity/facing/line-of-sight interaction, discovery and reset.
  The same prompts reach human, agent and spectator clients. Reuse MapInfo resend
  ordering after any geometry change and the existing mission state boundary.
- Add Shiv to the canonical weapon/inventory/combat contracts. Preserve the
  existing five weapon indices, unlimited arcade policy and resolved-shot feedback.
  Melee has explicit ownership but no magazine, reserve, reload or muzzle flash.
- Bump gameplay admission for content that requires the new contract. Preserve
  old arena clients and five-slot retained service records; appended weapon counts
  must not erase history or shift its meaning. Validate both boundaries and test
  compatibility explicitly. No new crate or scripting runtime.
- Use registered pixel art and the existing weapon presentation. New raster art
  follows the image workflow, with prompt/provenance and import verification.

## Verification

Prove blocked/open cache traversal, valid control reach, all four gate combinations,
malformed authoring, range/occlusion/facing rejection, duplicate use, late join,
retry, ordinary main-route completion without the secret, personal weapon claims,
Shiv ownership/reach/cover/cooldown/no-ammo behavior, and record compatibility.
Inspect a live walk into the cache, the first-person blade's idle/attack sequence,
agent interaction and spectator presentation. Repeat the full M01 route and
existing multi-map regressions. Run strict Rust, coverage, client checks and the
published tour; record real hardware and remaining art/pacing limits.

This is part of M01 completion, not proof that its final art or the full campaign
is finished. Disk saves, M02, other secrets and general moving platforms remain
separate required work.

## Checkpoint and continuation

The night checkpoint preserves server foundations, not a playable cache. M01's
map has not changed and no Shiv is placed. Existing released content remains on
`main`; this branch must stay a draft until the integration below is complete.

Implemented in the draft:

- Optional authored service cache, four precomputed collision/navigation states,
  server use handling and reset state. These paths still need dedicated tests.
- Appended Shiv contract, ownership and ammunition-free inventory handling;
  ranged weapons and the three-weapon arcade policy retain their existing roles.
- Five-slot record compatibility with a sixth counter when the Shiv is used.
- Candidate viewmodel and pickup icon, exact prompts and source hashes in
  `client/art/weapons/manifest.json`, and reproducible `tools/bake_shiv.gd` output.

Local checkpoint verification on Windows, Rust 1.98.1 and Godot 4.7.2:

| Check | Result |
|---|---|
| `cargo check --workspace --all-targets --locked` | Passed |
| `cargo fmt --all -- --check` | Passed |
| `cargo clippy --workspace --all-targets --locked -- -D warnings` | Passed |
| `cargo test --workspace --locked` | 735 passed, 2 existing ignored, 0 failed |
| Godot source bake and editor import | Passed, clean error log |
| Source and reduced sprite inspection | Passed as candidates, no live motion evidence |

New tests prove discovered ownership, repeat grants, no ammunition consumption,
invalid melee magazines, legacy record round trips, new counters and malformed
counter arrays. This does not establish cache navigation or combat correctness.
Logs are disposable under `.agents/shiv-*.log`. Full coverage, headless gameplay
harnesses, release builds, mixed-client roster and rendered tours have not been
rerun for this draft. No new release or visual-quality claim is appropriate.

Resume in this order:

1. Review the server geometry/state changes and add authored-cache tests for all
   four gate states, invalid controls, simultaneous main/cache use, retry and late
   join. Tighten secret state validation against the current geometry and attempt.
2. Align the authored JSON schema, both mission readers, shared controller and MCP
   schema/parser. The draft's capability 9 is not yet an end-to-end client promise.
   Add Shiv parsing to `agents/brain/src/plan.rs`; serialization alone is present.
3. Extend strict GDScript weapon, loadout, shot and record validators. Preserve
   five-slot disk history and append counters without changing existing indices.
   Add real melee animation, pickup presentation, selection and a quiet discovery
   notice. Reuse current audio routing; do not emit gunfire or a muzzle flash.
4. Author the actual M01 room, control and personal reward, keeping the main route
   independent. Prove traversal, discovery, combat reach/cover/cooldown and retry
   with players, agents and spectators. Inspect idle, walking and attack motion.
5. Complete the verification table above and the repository release gates, refresh
   the published tour, then update this plan and protocol from draft to shipped.

The last released graphics change is v0.33.0, PR #202. Its merged tree passed
[CI](https://github.com/blisspixel/fragr/actions/runs/35550793314). The full game,
remaining campaign missions and other roadmap modes are still unfinished.
