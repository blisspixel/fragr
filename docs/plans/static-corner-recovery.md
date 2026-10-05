# Static corner recovery

Status: implemented and independently verified, composed integration in flight,
2026-10-05.

Reclamation Gulch's twelve-client roster retained stationary episodes beside two east-ridge stair flights. The original report lacks height, target and action history, so it does not establish which controller branch caused those episodes. The unchanged main-job repeat passed. Separate actual-map diagnostics prove that ordinary non-forward combat intent can remain pinned at the recorded supported ground positions while a diagonal outward move can escape through unchanged geometry.

Extend only the existing `Navigator::avoid_bodies` recovery owner. After six consecutive stationary ticks against static cover, use the existing six-step movement and contact forecasts to choose a supported escape. Remember its movement combination for at most twelve ticks. Preserve target, aim, fire, pitch, equipment and sequence fields. Clear movement, jump, explicit reset and expiry must end this recovery. Keep ordinary unobstructed retreat, strafe and deliberate drops unchanged. Do not replace the hostile target, increase navigation search budgets, change movement math or solids, or relax the five-second CI stuck threshold and resolved `just_fired` semantics.

Inline owning-controller tests cover both actual corners for 120 ticks, ten consecutive moving steps after first escape, actual net progress, preserved action facts, clear retreat, reset, jump and unsupported drops both before and during an active escape lease. A deliberate unsupported drop ends an active lease before continuation can replace the original action. Existing crowd, supported-stair, mission-corner and search-cadence tests remain acceptance gates. A one-step early candidate and the initial active-lease drop redirection were rejected by their controls; both receipts are retained privately.

Focused controller tests, formatting, complete workspace/client checks and
denied-warning checks passed in the isolated development lane. Exact input
`51c33e16b9d4f64c4ae4f042c0818e87d1c9c684` passed all eight
[CI jobs](https://github.com/blisspixel/fragr/actions/runs/37262348864) and all
three [desktop package checks](https://github.com/blisspixel/fragr/actions/runs/37262347874).
The bounded original twelve-client case and one candidate case are separate
timing receipts, not deterministic counterfactuals. Socket participants have
independently assigned identities and asynchronous admission order. The
[composed integration](crew-companion-integration.md) repeats complete owning
gates against crew and companion changes before main acceptance. This is a
scoped controller correction; the original intermittent CI episode's
attribution remains open.
