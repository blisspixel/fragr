# Crew receipt and companion integration

Status: in flight, 2026-10-04. This bounded composition starts from restored
main `6c4df5b3afd30ade456955148c9c438580e31831`. It combines companion
checkpoint `2a601c66bb0878ac91111fde9d2e512c62b30238` and crew receipt
checkpoint `12e966af20cc5d6441ea7819897648cdacb8da08` through normal merges.
This is an integration gate within the existing Full build order.

## Scope

Preserve the bounded supported companion stand-off and short-yield movement,
including both delivered-contact regressions and the original finite combat
rules. Preserve the immutable M09 release and actual aboard-at-confirmation
receipt, strict version 12 storage and exact historical byte archives. M10
transit and historical unknown crew arrivals remain unimplemented.

Keep restored held Rifle artwork and every other selected asset unchanged.
Jammer, Railgun and replacement Rifle candidates stay offline. No new map,
geometry, difficulty, arrival tolerance, stress threshold or paid operation
belongs to this composition. The failed fresh-main map 5 mixed-client receipt
remains separate evidence, not a resolved failure attributed to these changes.

## Acceptance

1. Merge the two exact checkpoints without rewriting their history. Verify
   the composed changes against both leaves and restored main, including
   selected Rifle textures and the absence of candidate art substitutions.
2. Use a unique private native target with two build jobs. Run formatting,
   warning-denied all-target workspace Clippy, locked workspace tests, release
   build and the existing deterministic benchmark checks.
3. Run the complete client checker with the composed native beside the pinned
   engine. Require numeric exit 0, clean errors and every harness PASS.
   Retain prior actual route and persistence receipts as historical evidence;
   these integration checks do not claim a new rendered playthrough.
4. Record exact inputs, native hash, local counts and limitations in a unique
   integration evidence document. Refresh the single Full build order and
   plan index consistently, without introducing another active queue.
5. Publish one reviewable draft integration PR. Require all eight exact-head
   CI jobs and all three desktop package checks. Do not merge main or tag a
   release in this lane.

The private target and logs belong to this integration only. Existing native
executables, shader caches, failed receipts and prior worktrees stay intact.
External spend is $0.
