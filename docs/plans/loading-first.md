# Loading before the world

Status: **in flight**, 2026-10-04. Spend: $0. Parent sequence: the presentation
and controls work in ROADMAP.md, no additional global build order.

The initial game scene currently exposes its default arena while waiting for
MapInfo. The controls card appears later and dismisses on a four-second clock
independently of readiness. A direct debug launch can therefore show an empty
or wrong arena before its loading screen.

Reuse LoadingCard as an opaque startup curtain before connecting or building
the presentation. Its waiting state must ignore dismissal and must not present
a time-based progress bar as measured loading progress. Release that state
only after authoritative geometry and a matching snapshot are presented and
the first frame has drawn. Campaign story scenes can take over the opaque
cover, preserving their own input-release and readiness contract. Keep the
existing short controls card for human arena admission after loading.

Failed connections must show an observable error and offer return to the
menu. A disconnect or replacement map invalidates pending reveal callbacks.
Same-map authoritative gate/collapse updates must not introduce loading breaks
during combat. Automated trees remain isolated and never capture the pointer.

Verification: prove the first main-scene frame is covered, early keys and long
waits cannot expose the world, stale snapshots do not unlock a new map, errors
retain cover and return safely, and campaign opening/readiness still work.
Run focused lifecycle harnesses, a real rendered launch and full client/CI
checks before integration. This does not claim to fix the independently
unreproduced office-wall or intermittent blank-material report.

## Local evidence

The focused lifecycle check passes readiness, stale generation/snapshot,
failure cover and released-versus-held device input. The real local M08
saved-run check caught a fresh-press rearming race introduced by blocking
controls during loading. Rearming released grenade/mine keys at dismissal
fixes it while preserving held-key protection; the actual local-child check
passes again. Its original failed full-suite diagnostic remains retained.

A detached actual Compatibility renderer check on Radeon 780M exits 0 with
clean logs and the harness PASS marker. Inspected 1920x1280 captures show the
first game frame covered, geometry still covered before a matching snapshot,
an observable failed connection, then the rendered world after reveal. This
uses controlled delivery at actual presenter boundaries, not a complete
network playthrough or hardware performance benchmark. Full client and CI
verification remain required before shipping.
