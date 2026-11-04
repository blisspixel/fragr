class_name AimState
extends RefCounted

const INVALID: String = "The server sent invalid aim state. Connection closed."
const MAX_CONE: int = 190000
const RAISE_TICKS: Dictionary[String, int] = {
	"fists": 4, "shiv": 4, "tack": 4, "scatter": 4, "article_blade": 4,
	"flechette": 5, "repeater": 5, "arc": 5,
	"rail": 7, "sniper": 7, "rocket": 7,
}

static func validation_error(data: Dictionary, owner: Variant, previous: Dictionary = {}) -> String:
	if not owner is String or data.get("player_id") != owner:
		return INVALID
	if not EquipmentState.integer(data.get("tick"), EquipmentState.MAX_EXACT_INTEGER) \
			or not EquipmentState.integer(data.get("cone_microradians"), MAX_CONE):
		return INVALID
	if not data.get("weapon") is String or not RAISE_TICKS.has(data["weapon"]):
		return INVALID
	if not previous.is_empty() and int(data["tick"]) < int(previous["tick"]):
		return INVALID
	if data.has("raise_ready_at"):
		if not EquipmentState.integer(data["raise_ready_at"], EquipmentState.MAX_EXACT_INTEGER):
			return INVALID
		var remaining: int = int(data["raise_ready_at"]) - int(data["tick"])
		if remaining <= 0 or remaining > RAISE_TICKS[data["weapon"]]:
			return INVALID
	for key: Variant in data:
		if key not in ["type", "player_id", "tick", "weapon", "cone_microradians", "raise_ready_at"]:
			return INVALID
	return ""
