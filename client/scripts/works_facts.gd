class_name WorksFacts
extends RefCounted
## Validates the snapshot's restoration work facts: marked Paver strips and
## worn jetpacks. Presentation reads them; the server owns every outcome.

const INVALID: String = "The server sent invalid restoration work facts. Connection closed."
const MAX_STRIPS: int = 8
const STRIP_HALF_WIDTH: float = 1.6
const STRIP_MIN_LENGTH: float = 4.0
const STRIP_MAX_LENGTH: float = 15.0
## A Paver works the strip's floor band: feet within this of the strip's height.
const STRIP_FLOOR_BAND: float = 0.7
const PHASE_LIMIT: int = 100

static func validation_error(snapshot: Dictionary) -> String:
	var strips: Variant = snapshot.get("paver_strips", [])
	var packs: Variant = snapshot.get("jetpacks", [])
	if not strips is Array or strips.size() > MAX_STRIPS or not packs is Array or packs.size() > ActorState.MAX_PLAYERS:
		return INVALID
	var tick: Variant = snapshot.get("tick")
	if (not strips.is_empty() or not packs.is_empty()) and not EquipmentState.integer(tick, EquipmentState.MAX_EXACT_INTEGER):
		return INVALID
	var actors: Dictionary = {}
	for actor: Variant in snapshot.get("players", []):
		if actor is Dictionary:
			actors[str(actor.get("id", ""))] = actor
	var owners: Array[String] = []
	for strip: Variant in strips:
		if not M03MissionState._exact(strip, ["owner_id", "origin", "yaw", "length", "half_width", "working", "phase_started", "phase_ends"]) \
			or not MissionState._uuid(strip["owner_id"]) or strip["owner_id"] in owners \
			or not MissionState._point(strip["origin"], MapGeometry.MAX_HALF) \
			or not _number(strip["yaw"], 0.0, TAU) or not _number(strip["length"], STRIP_MIN_LENGTH, STRIP_MAX_LENGTH) \
			or not is_equal_approx(float(strip["half_width"]), STRIP_HALF_WIDTH) or not strip["working"] is bool \
			or not EquipmentState.integer(strip["phase_started"], int(tick)) \
			or not EquipmentState.integer(strip["phase_ends"], EquipmentState.MAX_EXACT_INTEGER) \
			or int(strip["phase_ends"]) < int(strip["phase_started"]) or int(strip["phase_ends"]) - int(strip["phase_started"]) > PHASE_LIMIT:
			return INVALID
		var owner: Variant = actors.get(strip["owner_id"])
		if not owner is Dictionary or not ActorState.is_hostile(owner) or owner["campaign"].get("kind") != "paver" \
			or owner["campaign"].get("phase") != ("firing" if strip["working"] else "windup"):
			return INVALID
		owners.append(strip["owner_id"])
	var wearers: Array[String] = []
	for pack: Variant in packs:
		if not M03MissionState._exact(pack, ["player_id", "fuel", "thrusting"]) or not MissionState._uuid(pack["player_id"]) \
			or pack["player_id"] in wearers or not EquipmentState.integer(pack["fuel"], JetMovement.FUEL_MAX) \
			or not pack["thrusting"] is bool or not actors.has(pack["player_id"]) \
			or not ActorState.is_participant(actors[pack["player_id"]]):
			return INVALID
		wearers.append(pack["player_id"])
	return ""

static func _number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= low and float(value) <= high

## Strip-local (along, across) coordinates of a world floor point.
static func strip_local(strip: Dictionary, x: float, z: float) -> Vector2:
	var yaw: float = float(strip["yaw"])
	var forward: Vector2 = Vector2(cos(yaw), sin(yaw))
	var lateral: Vector2 = Vector2(-forward.y, forward.x)
	var offset: Vector2 = Vector2(x - float(strip["origin"][0]), z - float(strip["origin"][2]))
	return Vector2(offset.dot(forward), offset.dot(lateral))

## A body is worked when its feet stand inside the strip on its floor band.
static func inside(strip: Dictionary, feet: Vector3) -> bool:
	var local: Vector2 = strip_local(strip, feet.x, feet.z)
	return local.x >= 0.0 and local.x <= float(strip["length"]) and absf(local.y) <= float(strip["half_width"]) \
		and absf(feet.y - float(strip["origin"][1])) <= STRIP_FLOOR_BAND

## The worn pack of one fighter, or empty.
static func pack_for(snapshot: Dictionary, player_id: String) -> Dictionary:
	for pack: Variant in snapshot.get("jetpacks", []):
		if pack is Dictionary and pack.get("player_id") == player_id:
			return pack
	return {}
