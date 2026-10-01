# Shot clearance at render time

**Status:** shipped in [PR #314](https://github.com/blisspixel/fragr/pull/314), 2026-09-30. **Spend:** $0.

The M04 aftermath capture exposed beige near-camera triangles. No Notary debris
system exists; their exact origin remains under review. The existing CPU shot
clip has a separate reproducible gap: prediction or camera presentation can move
the eye after effect geometry was built but before it is drawn. Add a small
opaque, unshaded vertex-color material that also enforces the existing 0.6m
clearance against the actual render camera. Preserve CPU clipping, resolved
evidence, lifetimes, depth tests and all authoritative shot behavior.

The rendered regression freezes a valid distant impact mesh, then moves the
camera inside its clearance without rebuilding that mesh. Capture the original
material filling the aiming pixel, the new material clearing it, and distant
impact retention. Run the existing shot-effects harness, actual Compatibility
render proof and final tour. Do not call the original M04 artifact fixed until
its later capture is inspected. No new dependency or runtime service.

The live companion's radial 0.7m clip also permits close peripheral geometry
outside the sphere but inside the view-depth clearance. Use the same actual
camera-depth rule on its opt-in material, keeping shadow passes and the passive
ward unchanged. A rendered upward-looking regression checks the upper view for
those close fragments. Distant opacity, material properties, authoritative body
and shot blocking stay unchanged.

## Final evidence

Focused headless shot checks and isolated actual Compatibility renders passed
cleanly, exit 0. Logs under `.agents/m04-buildout-20260930/` are
`shot-camera-headless.log`, `shot-camera-rendered-isolated.log` and
`latch-camera-depth-rendered.log`. The frozen stale impact fills the aiming pixel
with its original material, clears with actual-camera clipping and remains visible
at distance. The upward companion regression has no changed upper-view pixels;
the ordinary distant chassis, shadow behavior and ward materials remain intact.
Initial renderer runs that reported resource errors remain failed diagnostics.

The final full checker passed 163 scripts and 76 harnesses. The actual
`.agents/qa/m04-market-ninth/06_notary_lesson_defeat.png` was inspected: the large
sky triangles seen in the earlier capture are gone. The full 23-state route also
passed. No debris system, gameplay pass-through or universal hardware guarantee
is inferred from these bounded rendering corrections.
