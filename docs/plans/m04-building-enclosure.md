# M04 building enclosure

**Status:** shipped with main integration of PR #347, 2026-10-03;
[PR #343](https://github.com/blisspixel/fragr/pull/343) records the reviewed source
and all eight passing CI jobs. Combined main integration is consolidated into
[PR #347](https://github.com/blisspixel/fragr/pull/347), with its own complete gate.
Nick found the played buildings oddly open.
Rendered review confirms the clinic and workshop have perimeter walls but no
ceilings. The market and courtyard are intentionally outdoors.

## Goal and boundary

Make the clinic and workshop read as enclosed inhabited rooms at player height.
Add roof slabs to the existing authored map, with sufficient headroom for doors,
the lifted clinic shutter and actual patient/player routes. Render their real
undersides with the venue materials and existing lighting. Do not hide missing
walls with fog or introduce cosmetic roofs that disagree with shot collision.

Preserve encounter order, gate state, release and safe patient routes, supplies,
roof departure, water patches and existing furniture. Court facade depth and
broader town building volumes remain subsequent authored architecture work.
Do not change difficulty timing, protocol, campaign revision or server authority.

## Implementation and verification

Use registered static solids in the existing M04 map and its two precomputed
clinic worlds. Check the lifted shutter does not intersect a roof. Reuse map
validation and navigation proofs, then run the complete ordinary-input M04
route with all original encounter/clinic/departure states. Inspect clinic and
workshop ceiling/wall joins from player height and the roof departure sightline.
Keep optional patients traversable and all route failures visible. Run focused
authoring/client checks followed by the required full CI before main integration.

No paid assets or new dependency are required. Coordinate this map change with
the independently owned M04 surface detail lane and M07 shared mission changes.

## Implemented enclosure and acceptance

Eight real map solids close the clinic and workshop at a 4 m underside and
enclose the lifted clinic shutter above a 6.2 m pocket. Existing enamel finishes
and venue light describe the actual blocking surfaces. The outdoor court keeps
its open sky and civilian palette.

All 25 focused M04 Rust tests pass, including resolved vertical shot obstruction
inside each room, unchanged open-air rays, shutter clearance and both prepared
clinic worlds. Workspace warning-denied clippy and format checks pass.
The historical-save harness also passes with the matching bundled native map;
its earlier rejection came from an older executable's different map hash.
The full combined client checker passes all 224 scripts and 103 harnesses with
exit 0, its own PASS marker and clean error logs. The checker fault-injection
suite also passes all ten scenarios. Final full CI gates main integration.

The [clean rendered route](../evidence/m04-building-enclosure-20261003.md)
completes all 29 states, all 28 named guards, clinic release and actual departure
with zero deaths, zero HP lost and 70 armor lost. The evidence retains earlier
failures and the concrete ordinary-input corrections. The canonical roof-return
route now keeps its arrival disk on the supported crossing and explicitly visits
the existing half-metre tread. No collision bypass, jump grant, damage change or
weaker mission gate is introduced. Broader facade volumes and human acceptance
remain separate work.
