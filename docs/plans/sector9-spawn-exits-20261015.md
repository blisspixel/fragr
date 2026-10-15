# Sector 9 freight-bay exits

Status: **implemented**, integration pending, 2026-10-15. Broad integration exposed a Sabotage plant-area
and holding-spot overlap in the second candidate. Its native, network and
independently inspected traversal evidence remains in
[the receipt](../evidence/sector9-spawn-exits-20261015.md). A corrected third
candidate passes scoped movement/combat checks, five-seed live comparison,
all required network and roster checks, inspected affected passages and final
composed native gates. A bounded existing-arena
refinement under Full build order rung 1. Parent integration owns the roadmap
and plan index.

## Goal and evidence

Give fighters a readable covered first decision when leaving Sector 9's freight
bays. The October 15 eight-client roster recorded six deaths within forty ticks
of spawning, all after movement roughly four to nine metres from the bay. Its
opening recorded zero deaths. These positions describe observed firing lanes,
not an exact replay or proof that spawn placement itself was invalid.

The selector scores current visibility at a spawn point. Existing three-block
pockets screen that point but open directly toward the interior. Reconstruct
the retained lanes before changing map-local geometry. Preserve useful fight
contact, alternate routes and the freight-interchange identity.

## Scope and architecture

Own only Sector 9's `sector_9()` solids in `server/src/maps.rs`, focused native
regressions and this plan/evidence. Reuse authoritative solids and existing
materials. No global pocket change, spawn selector change, invulnerability
extension, damage rebalance, CTF policy/rule change, dependency or wire addition.
Client MapInfo remains the sole geometry source. Preserve walking, pickups,
flag routes and other venues. Current campaign work owns separate authored maps.

`docs/MAP-DESIGN.md` requires answerable lanes with nearby cover and meaningful
route choices rather than filler. Epic's primary
[level-design guidance](https://dev.epicgames.com/documentation/fortnite/level-design-best-practices-in-fortnite-creative?lang=en-US),
checked October 15, recommends avoiding single-entry fight areas and using lane
structure for team objectives. Apply those spatial principles to fragr's own
movement and freight architecture; no borrowed map or art.

## Implementation and acceptance

1. Preserve a release baseline, run eight alternating Reflex/Planner clients on
   Sector 9 for seeds 40 through 44, one round, eight-frag target, sixty-second
   clock and unchanged assertions. Retain all reports and failed observations.
2. Add deterministic tests reconstructing recorded exit lanes and actual normal
   movement. Establish the failing current geometry before adding bounded
   freight cover. Cover must offer a normally walkable exit and another approach
   without enclosing the spawn, obstructing pickups or creating a route stall.
3. Repeat exactly the five live observations. Report pooled early-death rate,
   openings, frags, match time and stalls; improvements require the table, not a
   selected successful seed. If the geometry fails those checks, revise or
   withhold it rather than lowering assertions.
4. Run focused spawn/geometry/navigation checks, every existing Sabotage zone
   and timing check, actual CTF route and contested checks, and a Sector 9 team
   match. Preserve ordinary routes for both sides in every shared map mode.
   Parent integration coordinates broad native gates and inspected rendered
   motion. Human enjoyment, physical LAN and final map acceptance remain open.

## Spend and delivery

$0. No asset production, external API credit, cloud operation or deployment.
No commits/pushes from this lane. Record failures, final checks, limitations and
the measured comparison in `docs/evidence/sector9-spawn-exits-20261015.md` before
marking local implementation complete.
