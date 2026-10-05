# Shiv hand scale

Status: in flight, 2026-10-05. Presentation-only correction from main
`d511a0ed`. The separate continuity audit found an extra 1.3 resting scale
on the entire Shiv picture, enlarging the same player's glove and wrist.
No provider request, new hand source or weapon gameplay change is needed.

## Bounded change

Remove the additional resting enlargement. Keep the selected picture,
lower-right pivot, ordinary bob, existing resolved-use thrust and 22 percent
forward growth. The original blade remains a substantial readable silhouette;
do not cut it from the hand, change pixel filtering or increase a shared gun
control to recover its former size. Preserve original Fists and gun behavior.

Use actual HUD transforms and named source-pixel glove landmarks to compare
resting and settled Shiv hand scale with Shotgun, including multiple aspect
ratios. Check actual transformed base/opaque source coverage during ordinary
walking and repeated resolved-use poses. Retain all original canonical
viewmodel thresholds. Static aspect/bob tests do not prove visual acceptance.

## Acceptance

- Owning viewmodel and gesture harnesses pass with clean error logs.
- Source artwork remains byte-identical; rest/settle use the same source-pixel
  display scale as Shotgun, while deliberate use reach remains visible.
- Original opaque bottom, scope, gun fire, fists, grenade/mine and bob behavior
  continue to pass.
- CPU old/new display projection is inspected, then a separately authorized
  actual rendered comparison establishes hand proportion and blade readability.
  No promotion before that review. No hardware lease has been taken yet.

Root owns integration, global documentation and publication.

## Verified bounded checkpoint

Production changes only `FP_SHIV_SCALE` from 1.3 to 1.0. The existing lower-right
pivot, 22 percent reach, lateral thrust, bob and all selected pixels remain.
The new owning `test_viewmodel.gd` regression fails six rest/settle comparisons
on the original value, then passes on the correction. It compares actual
transformed cuff texels with Shotgun at 1280 by 720, 1024 by 768 and 2560 by
1080. Sixty use samples per aspect also prove actual transformed opaque wrist
coverage at the physical window bottom. All original gun, Fists, scope,
throw, bob, frame and resize checks remain unchanged and pass.

Actual standalone HUD rendering produced 18 old/new frames for rest, half-use
and bob across the same three sizes. Renderer 11816 exits 0, error-clean and
retired; there was no server, gameplay authority or pointer capture. The old
extra 1.3 scale was reapplied only to the actual control between paired
captures, then restored. Every actual image/window size and hash matches
its receipt. Selected artwork SHA-256 remains
`e7a13b4bbc918ace97910ac9f3ec1c44fecdc0e2a6e7a0b8920804ff8d5035c8`.
The reduced hand and blade are visibly distinct at all inspected aspects,
with a continuous wrist entry; source and presentation checks do not claim
a new played combat route or universal human preference.

Evidence is private under `.agents/shiv-hand-scale-20261005/.agents/`:
`viewmodel-before.log` retains the six original failures;
`viewmodel-transform.log` is the clean corrected canonical PASS;
`render-first.log`, `render-first/receipt.json` and `receipt-check.log` retain
actual numeric renderer exit, PID, capture dimensions and source hashes.
Receipt SHA-256 is
`dff60f2106569dfd904aa133de2141fe4f368756a1bb7e04916d7e6528507e73`.
Two mistyped optional harness names failed as missing files and remain
diagnostic logs; they are not claimed tests. Root's visual review and composed
integration gates are still pending. No push or runtime promotion in this lane.
