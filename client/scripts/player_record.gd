class_name PlayerRecord
extends RefCounted

## Mirror of protocol/statistics.rs. Display and persistence share this boundary.
const VERSION: int = 1
const STATUSES: Array[String] = ["active", "continue", "complete", "failed", "abandoned"]
const COUNTS: Array[String] = ["alive_ticks", "deaths", "hp_lost", "armor_lost", "dry_triggers"]
const WEAPON_COUNTS: Array[String] = ["attacks", "damaging_attacks", "kills", "hp_damage", "armor_damage"]
const INVALID: String = "Invalid participant record."

static func terminal(record: Dictionary) -> bool:
	return record.get("status") in ["complete", "failed", "abandoned"]

static func key(record: Dictionary) -> String:
	return "%s/%s/%d" % [record["session_id"], record["player_id"], int(record["round"])]

static func validation_error(data: Dictionary, owner: Variant, previous: Dictionary = {}) -> String:
	if data.size() != (16 if data.has("type") else 15) or (data.has("type") and data["type"] != "record") \
		or data.get("version") != VERSION or data.get("ticks_per_second") != 20 \
		or not MissionState._uuid(data.get("session_id")) or not MissionState._uuid(data.get("player_id")) \
		or data.get("player_id") != owner or data.get("role") not in ["human", "agent"] \
		or data.get("status") not in STATUSES:
		return INVALID
	for field: String in ["version", "ticks_per_second", "round", "tick", "map_id", "entered_at", "round_started_at"]:
		if not EquipmentState.integer(data.get(field), EquipmentState.MAX_EXACT_INTEGER):
			return INVALID
	if int(data["entered_at"]) > int(data["tick"]) or int(data["round_started_at"]) > int(data["entered_at"]):
		return INVALID
	if int(data["round"]) < 1 or int(data["round"]) > 4294967295 or int(data["map_id"]) < 1 or int(data["map_id"]) > 4294967295 \
		or not data.get("map_name") is String or data["map_name"].is_empty() or data["map_name"].length() > 128:
		return INVALID
	if not valid_counts(data.get("total")) or not valid_counts(data.get("attempt")):
		return INVALID
	if int(data["total"]["alive_ticks"]) > int(data["tick"]) - int(data["entered_at"]):
		return INVALID
	if not contains(data["total"], data["attempt"]) or not _valid_scope(data):
		return INVALID
	if not previous.is_empty():
		if data["session_id"] != previous["session_id"] or data["player_id"] != previous["player_id"] \
			or int(data["tick"]) < int(previous["tick"]) or int(data["round"]) < int(previous["round"]):
			return INVALID
		if data["round"] == previous["round"]:
			if data["map_id"] != previous["map_id"] or data["map_name"] != previous["map_name"] \
				or data["entered_at"] != previous["entered_at"] or data["round_started_at"] != previous["round_started_at"] \
				or data["role"] != previous["role"] or not contains(data["total"], previous["total"]) \
				or not _scope_follows(data["scope"], previous["scope"]):
				return INVALID
			var attempt: int = int(data["scope"].get("attempt", 1))
			var old_attempt: int = int(previous["scope"].get("attempt", 1))
			if attempt < old_attempt or (attempt == old_attempt and not contains(data["attempt"], previous["attempt"])):
				return INVALID
			if terminal(previous) and (data["status"] != previous["status"] or data["total"] != previous["total"] \
				or data["scope"] != previous["scope"] or data["attempt"] != previous["attempt"]):
				return INVALID
	return ""

static func valid_counts(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 6 or not value.get("weapons") is Array or value["weapons"].size() != 5:
		return false
	for field: String in COUNTS:
		if not EquipmentState.integer(value.get(field), EquipmentState.MAX_EXACT_INTEGER):
			return false
	for weapon: Variant in value["weapons"]:
		if not weapon is Dictionary or weapon.size() != 5:
			return false
		for field: String in WEAPON_COUNTS:
			if not EquipmentState.integer(weapon.get(field), EquipmentState.MAX_EXACT_INTEGER):
				return false
		if int(weapon["kills"]) > int(weapon["damaging_attacks"]) or int(weapon["damaging_attacks"]) > int(weapon["attacks"]):
			return false
	for field: String in WEAPON_COUNTS:
		if sum_weapon(value, field) > EquipmentState.MAX_EXACT_INTEGER:
			return false
	if sum_weapon(value, "attacks") > int(value["alive_ticks"]) or int(value["deaths"]) > int(value["alive_ticks"]) or int(value["dry_triggers"]) > int(value["alive_ticks"]):
		return false
	return true

static func contains(total: Dictionary, part: Dictionary) -> bool:
	for field: String in COUNTS:
		if int(total[field]) < int(part[field]):
			return false
	for index: int in range(5):
		for field: String in WEAPON_COUNTS:
			if int(total["weapons"][index][field]) < int(part["weapons"][index][field]):
				return false
	return true

static func _valid_scope(data: Dictionary) -> bool:
	var scope: Variant = data.get("scope")
	if not scope is Dictionary:
		return false
	if scope.get("kind") in ["arena", "practice"]:
		return scope.size() == 2 and EquipmentState.integer(scope.get("round"), 4294967295) and scope.get("round") == data["round"] and data["attempt"] == data["total"]
	if scope.get("kind") != "mission" or scope.size() != 5 or scope.get("mission") != MissionState.ID \
		or not EquipmentState.integer(scope.get("attempt"), 4294967295) or int(scope["attempt"]) < 1 \
		or not MissionState.valid_rules(scope.get("rules")) or not scope.has("run"):
		return false
	if scope["run"] == null:
		return true
	var run: Variant = scope["run"]
	if not MissionState.valid_run_identity(run, scope["attempt"]):
		return false
	return data["status"] == ("active" if run["status"] == "playing" else run["status"])

static func _scope_follows(value: Dictionary, old: Dictionary) -> bool:
	if value["kind"] != old["kind"]:
		return false
	if value["kind"] != "mission":
		return value == old
	if value["mission"] != old["mission"] or value["rules"] != old["rules"]:
		return false
	return MissionState.run_follows(value["run"], old["run"])

static func sum_weapon(counts: Dictionary, field: String) -> int:
	var total: int = 0
	for weapon: Dictionary in counts["weapons"]:
		total += int(weapon[field])
	return total

static func empty_counts() -> Dictionary:
	var counts: Dictionary = {"weapons": []}
	for field: String in COUNTS:
		counts[field] = 0
	for index: int in range(5):
		var weapon: Dictionary = {}
		for field: String in WEAPON_COUNTS:
			weapon[field] = 0
		counts["weapons"].append(weapon)
	return counts

static func add_counts(total: Dictionary, value: Dictionary) -> void:
	for field: String in COUNTS:
		total[field] = int(total[field]) + int(value[field])
	for index: int in range(5):
		for field: String in WEAPON_COUNTS:
			total["weapons"][index][field] = int(total["weapons"][index][field]) + int(value["weapons"][index][field])
