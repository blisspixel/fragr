class_name CombatDuck
extends RefCounted

## How much a fight near the listener lowers music: the radio and the
## campaign score both read this one heat, so combat always ducks them
## (docs/plans/fun-craft-targets.md section 8: radio and music sit under
## everything that carries information). Presentation only: the heat comes
## from resolved shots and explosions the server sent.

## Full heat lowers music by this much.
const FULL_DB: float = -9.0
## Heat per counted shot and per counted blast; it drains each second.
const PER_SHOT: float = 0.08
const PER_BLAST: float = 0.25
const COOL_PER_SECOND: float = 0.35
const MAX_HEAT: float = 1.5
## A shot or blast this close to the listener counts; farther fights are
## somebody else's.
const HEAR_DISTANCE: float = 40.0

var heat: float = 0.0


## Shots and blasts this tick, weighted.
func add(shots: int, blasts: int) -> void:
	heat = minf(heat + PER_SHOT * float(maxi(shots, 0)) + PER_BLAST * float(maxi(blasts, 0)), MAX_HEAT)


func cool(delta: float) -> void:
	heat = maxf(heat - COOL_PER_SECOND * maxf(delta, 0.0), 0.0)


func duck_db() -> float:
	return db_for(heat)


static func db_for(value: float) -> float:
	return FULL_DB * clampf(value, 0.0, 1.0)


## Which of this tick's resolved shots belong to the listener's fight: fired
## by or at `listener_id`, or fired from within HEAR_DISTANCE of `listener`.
## `positions` maps fighter ids to world positions.
static func shots_near(results: Variant, listener_id: String, listener: Vector3, positions: Dictionary) -> int:
	if not results is Array:
		return 0
	var count: int = 0
	for result: Variant in results:
		if not result is Dictionary:
			continue
		var shooter: String = str((result as Dictionary).get("shooter_id", ""))
		var target: String = str((result as Dictionary).get("target_id", ""))
		if not listener_id.is_empty() and (shooter == listener_id or target == listener_id):
			count += 1
			continue
		var at: Variant = positions.get(shooter)
		if at is Vector3 and listener.is_finite() and (at as Vector3).distance_to(listener) <= HEAR_DISTANCE:
			count += 1
	return count


## Blasts this tick within HEAR_DISTANCE of the listener.
static func blasts_near(explosions: Variant, listener: Vector3) -> int:
	if not explosions is Array or not listener.is_finite():
		return 0
	var count: int = 0
	for blast: Variant in explosions:
		if not blast is Dictionary:
			continue
		var position: Variant = (blast as Dictionary).get("position")
		if not position is Array or (position as Array).size() != 3:
			continue
		var values: Array = position
		if not (values[0] is float or values[0] is int) or not (values[1] is float or values[1] is int) or not (values[2] is float or values[2] is int):
			continue
		var at: Vector3 = Vector3(float(values[0]), float(values[1]), float(values[2]))
		if at.is_finite() and at.distance_to(listener) <= HEAR_DISTANCE:
			count += 1
	return count
