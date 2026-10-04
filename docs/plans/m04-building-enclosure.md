# M04 building enclosure

**Status:** in flight, 2026-10-03. Nick found the played buildings oddly open.
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
