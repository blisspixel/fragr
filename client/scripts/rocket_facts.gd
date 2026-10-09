class_name RocketFacts
extends RefCounted

## Traveling rockets. Presentation only; the server owns flight and blasts.
const INVALID: String = "Invalid rocket snapshot."
const MAX_ACTIVE: int = 64
const PER_OWNER: int = 8
const LIFE_TICKS: int = 79

static func validation_error(snapshot: Dictionary) -> String:
	var facts: Variant = snapshot.get("rockets", [])
	if not facts is Array or facts.size() > MAX_ACTIVE:
		return INVALID
	if facts.is_empty():
		return ""
	var actors: Variant = snapshot.get("players", [])
	if not actors is Array or not EquipmentState.integer(snapshot.get("tick"), EquipmentState.MAX_EXACT_INTEGER):
		return INVALID
	var roster: Dictionary[String, bool] = {}
	for actor: Variant in actors:
		if actor is Dictionary and actor.get("id") is String:
			roster[str(actor["id"])] = true
	var counts: Dictionary[String, int] = {}
	var ids: Array[int] = []
	for key: String in ["grenades", "mines", "remote_mines", "projectiles", "explosions", "assessor_canisters"]:
		var others: Variant = snapshot.get(key, [])
		if not others is Array:
			return INVALID
		for other: Variant in others:
			if not other is Dictionary or not EquipmentState.integer(other.get("id"), 4294967295):
				return INVALID
			ids.append(int(other["id"]))
	for fact: Variant in facts:
		if not M03MissionState._exact(fact, ["id", "owner_id", "position", "velocity", "age_ticks"]) \
			or not EquipmentState.integer(fact["id"], 4294967295) or int(fact["id"]) < 1 \
			or int(fact["id"]) in ids or not MissionState._uuid(fact["owner_id"]) \
			or fact["owner_id"] == "00000000-0000-0000-0000-000000000000" \
			or not roster.has(str(fact["owner_id"])) or not _point(fact["position"], 1024.0) \
			or not _point(fact["velocity"], 20.0) or not EquipmentState.integer(fact["age_ticks"], LIFE_TICKS) \
			or int(fact["age_ticks"]) > int(snapshot["tick"]):
			return INVALID
		ids.append(int(fact["id"]))
		var owner: String = str(fact["owner_id"])
		counts[owner] = int(counts.get(owner, 0)) + 1
		if counts[owner] > PER_OWNER:
			return INVALID
	return ""

static func _point(value: Variant, limit: float) -> bool:
	if not GrenadeFacts.point(value):
		return false
	for number: Variant in value:
		if absf(float(number)) > limit:
			return false
	return true
