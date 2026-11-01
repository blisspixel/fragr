class_name ShotZone
extends RefCounted

## Where a damaging traced hit landed, as the server reported it in
## `ShotResult.zone`. Presentation only: the server owns the zone and the
## damage it scaled. Head, torso and legs are height bands on a body;
## `plate` is issued armour that turned part of the hit; `weak` is a weak
## spot (a Union bot's red optic or the cyan light in its place, a Heavy
## Sweeper's rear vent, a Ranged Sweeper's mast, an open lens).

const HEAD: String = "head"
const TORSO: String = "torso"
const LEGS: String = "legs"
const PLATE: String = "plate"
const WEAK: String = "weak"
const NONE: String = ""

## The server's ranking for a result whose pellets struck several zones.
const RANK: Dictionary[String, int] = {LEGS: 0, TORSO: 1, PLATE: 2, HEAD: 3, WEAK: 4}


## The zone a wire value names, or NONE for a missing or unknown value.
static func parse(value: Variant) -> String:
	if value is String and RANK.has(value):
		return value
	return NONE


## The zone of one shot result, validated at the boundary.
static func of(result: Dictionary) -> String:
	return parse(result.get("zone"))


## The more telling of two zones, so a folded blast reports what the server
## would have reported for one result.
static func most_telling(a: String, b: String) -> String:
	if not RANK.has(b):
		return a if RANK.has(a) else NONE
	if not RANK.has(a):
		return b
	return a if RANK[a] >= RANK[b] else b
