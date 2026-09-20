class_name EquipmentState
extends RefCounted

## Private server inventory. These limits validate presentation, never award ammo.
const VERSION: int = 2
const WEAPONS: Array[String] = ["fists", "tack", "flechette", "scatter", "rail"]
const MAGAZINES: Dictionary = {"fists": 0, "tack": 12, "flechette": 30, "scatter": 6, "rail": 4}
const POOLS: Dictionary = {"tack": "tacks", "flechette": "darts", "scatter": "darts", "rail": "cores"}
const CAPACITIES: Dictionary = {"tacks": 220, "darts": 120, "cores": 100}
const RELOAD_TICKS: Dictionary = {"tack": 18, "flechette": 22, "scatter": 26, "rail": 28}
const MAX_EXACT_INTEGER: int = 9007199254740991

static func integer(value: Variant, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) \
		and float(value) >= 0.0 and float(value) <= maximum and float(value) == floorf(float(value))

static func validation_error(data: Dictionary, owner: Variant, previous: Dictionary = {}) -> String:
	const INVALID: String = "The server sent invalid equipment. Connection closed."
	if not owner is String or data.get("player_id") != owner:
		return INVALID
	if not integer(data.get("tick"), MAX_EXACT_INTEGER) or not integer(data.get("dry_fire_count"), MAX_EXACT_INTEGER):
		return INVALID
	if not previous.is_empty() and int(data["tick"]) < int(previous["tick"]):
		return INVALID
	if not data.get("selected") is String or not data.get("weapons") is Array \
		or not data.get("reserves") is Array or not data.get("personal_claims") is Array or not data.has("reload"):
		return INVALID
	var weapons: Array = data["weapons"]
	var reserves: Array = data["reserves"]
	var claims: Array = data["personal_claims"]
	if weapons.is_empty() or weapons.size() > WEAPONS.size() or reserves.size() != CAPACITIES.size() or claims.size() > 128:
		return INVALID
	var owned: Dictionary = {}
	for entry in weapons:
		if not entry is Dictionary or not entry.get("weapon") is String or not entry.has("magazine"):
			return INVALID
		var weapon: String = entry["weapon"]
		if not MAGAZINES.has(weapon) or owned.has(weapon):
			return INVALID
		if weapon == "fists":
			if entry["magazine"] != null:
				return INVALID
		elif not integer(entry["magazine"], MAGAZINES[weapon]):
			return INVALID
		owned[weapon] = entry["magazine"]
	if not owned.has("fists") or not owned.has(data["selected"]):
		return INVALID
	var pools: Dictionary = {}
	for entry in reserves:
		if not entry is Dictionary or not entry.get("pool") is String:
			return INVALID
		var pool: String = entry["pool"]
		if not CAPACITIES.has(pool) or pools.has(pool) or not integer(entry.get("rounds"), CAPACITIES[pool]):
			return INVALID
		pools[pool] = int(entry["rounds"])
	var claimed: Dictionary = {}
	for claim in claims:
		if not claim is String or claim.is_empty() or claim.length() > 64 or claimed.has(claim):
			return INVALID
		for character in claim:
			if character not in "abcdefghijklmnopqrstuvwxyz0123456789_":
				return INVALID
		claimed[claim] = true
	var reload: Variant = data["reload"]
	if reload != null:
		if not reload is Dictionary or not reload.get("weapon") is String:
			return INVALID
		var weapon: String = reload["weapon"]
		if not RELOAD_TICKS.has(weapon) or weapon != data["selected"] \
			or not integer(reload.get("complete_at"), MAX_EXACT_INTEGER):
			return INVALID
		var remaining: int = int(reload["complete_at"]) - int(data["tick"])
		if remaining <= 0 or remaining > int(RELOAD_TICKS[weapon]) \
			or int(owned[weapon]) == int(MAGAZINES[weapon]) or int(pools[POOLS[weapon]]) < (4 if weapon == "scatter" else 1):
			return INVALID
	return ""

static func magazine(state: Dictionary, weapon: String) -> int:
	for entry: Dictionary in state.get("weapons", []):
		if entry["weapon"] == weapon:
			return int(entry["magazine"]) if entry["magazine"] != null else 0
	return 0

static func reserve(state: Dictionary, weapon: String) -> int:
	for entry: Dictionary in state.get("reserves", []):
		if entry["pool"] == POOLS.get(weapon, ""):
			return int(entry["rounds"])
	return 0

static func cycle(state: Dictionary, current: String, step: int) -> String:
	var owned: Array[String] = []
	for entry: Dictionary in state["weapons"]:
		owned.append(entry["weapon"])
	return owned[posmod(maxi(0, owned.find(current)) + step, owned.size())]

static func reload_progress(state: Dictionary, tick: int) -> float:
	var reload: Variant = state.get("reload")
	if reload == null:
		return 0.0
	var duration: int = RELOAD_TICKS[reload["weapon"]]
	return clampf(1.0 - float(int(reload["complete_at"]) - tick) / duration, 0.0, 1.0)
