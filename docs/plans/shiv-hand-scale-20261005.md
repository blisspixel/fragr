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
