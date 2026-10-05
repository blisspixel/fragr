class_name PlayerRecord
extends RefCounted

## Mirror of protocol/statistics.rs. Display and persistence share this boundary.
const VERSION: int = 2
const LEGACY_VERSION: int = 1
const LEGACY_MAX_WEAPONS: int = 7
const STATUSES: Array[String] = ["active", "continue", "complete", "failed", "abandoned"]
const COUNTS: Array[String] = ["alive_ticks", "deaths", "hp_lost", "armor_lost", "dry_triggers"]
const WEAPON_COUNTS: Array[String] = ["attacks", "damaging_attacks", "kills", "hp_damage", "armor_damage"]
## Counted explosive columns, each omitted while unused.
const EXPLOSIVE_COLUMNS: Array[String] = ["grenades", "mines", "remote_mines"]
## Five original weapon slots, and a sixth once the Shiv has been used.
const LEGACY_WEAPONS: int = 5
const INVALID: String = "Invalid participant record."

static func terminal(record: Dictionary) -> bool:
	return record.get("status") in ["complete", "failed", "abandoned"]

static func key(record: Dictionary) -> String:
	return "%s/%s/%d" % [record["session_id"], record["player_id"], int(record["round"])]

static func validation_error(data: Dictionary, owner: Variant, previous: Dictionary = {}) -> String:
	if data.size() != (16 if data.has("type") else 15) + int(data.has("mission_elapsed_ticks")) or (data.has("type") and data["type"] != "record") \
		or (data.get("version") != LEGACY_VERSION and data.get("version") != VERSION) or data.get("ticks_per_second") != 20 \
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
	if not valid_counts(data.get("total"), int(data["version"])) or not valid_counts(data.get("attempt"), int(data["version"])):
		return INVALID
	if int(data["total"]["alive_ticks"]) > int(data["tick"]) - int(data["entered_at"]):
		return INVALID
	if not contains(data["total"], data["attempt"]) or not _valid_scope(data):
		return INVALID
	if data.has("mission_elapsed_ticks") and (not EquipmentState.integer(data["mission_elapsed_ticks"], EquipmentState.MAX_EXACT_INTEGER) \
		or data["status"] != "complete" or data["scope"]["kind"] != "mission" \
		or int(data["mission_elapsed_ticks"]) > int(data["tick"]) - int(data["round_started_at"])):
		return INVALID
	if not previous.is_empty():
		if data["session_id"] != previous["session_id"] or data["player_id"] != previous["player_id"] or data["version"] != previous["version"] \
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
				or data["scope"] != previous["scope"] or data["attempt"] != previous["attempt"] \
				or data.get("mission_elapsed_ticks") != previous.get("mission_elapsed_ticks")):
				return INVALID
	return ""

static func valid_counts(value: Variant, record_version: int = VERSION) -> bool:
	if not value is Dictionary or not value.get("weapons") is Array:
		return false
	var width: int = value["weapons"].size()
	if (record_version == LEGACY_VERSION and (width < LEGACY_WEAPONS or width > LEGACY_MAX_WEAPONS)) \
		or (record_version == VERSION and width != EquipmentState.WEAPONS.size()) \
		or record_version not in [LEGACY_VERSION, VERSION]:
		return false
	# Distinct secrets found; omitted while zero.
	var secrets: bool = value.has("secrets")
	if record_version == LEGACY_VERSION and value.has("remote_mines"):
		return false
	if value.size() != 6 + int(secrets) + int(value.has("grenades")) + int(value.has("mines")) + int(value.has("remote_mines")):
		return false
	if secrets and (not EquipmentState.integer(value["secrets"], EquipmentState.MAX_EXACT_INTEGER) 		or int(value["secrets"]) < 1 or int(value["secrets"]) > int(value.get("alive_ticks", 0))):
		return false
	for field: String in COUNTS:
		if not EquipmentState.integer(value.get(field), EquipmentState.MAX_EXACT_INTEGER):
			return false
	# Counted explosives keep their own columns beside the gun slots.
	for column: String in EXPLOSIVE_COLUMNS:
		if not value.has(column):
			continue
		var device: Variant = value[column]
		if not device is Dictionary or device.size() != 5:
			return false
		for field: String in WEAPON_COUNTS:
			if not EquipmentState.integer(device.get(field), EquipmentState.MAX_EXACT_INTEGER):
				return false
		if int(device["damaging_attacks"]) > int(device["attacks"]) or int(device["kills"]) > int(device["damaging_attacks"]) * 256:
			return false
	for index: int in range(value["weapons"].size()):
		var weapon: Variant = value["weapons"][index]
		if not weapon is Dictionary or weapon.size() != 5:
			return false
		for field: String in WEAPON_COUNTS:
			if not EquipmentState.integer(weapon.get(field), EquipmentState.MAX_EXACT_INTEGER):
				return false
		# One scatter blast can kill every fighter its pellets reach.
		var pellets: int = EquipmentState.pellets(EquipmentState.WEAPONS[index])
		if int(weapon["kills"]) > int(weapon["damaging_attacks"]) * pellets or int(weapon["damaging_attacks"]) > int(weapon["attacks"]):
			return false
	for field: String in WEAPON_COUNTS:
		if sum_combat(value, field) > EquipmentState.MAX_EXACT_INTEGER:
			return false
	if sum_combat(value, "attacks") > int(value["alive_ticks"]) or int(value["deaths"]) > int(value["alive_ticks"]) or int(value["dry_triggers"]) > int(value["alive_ticks"]):
		return false
	return true

static func contains(total: Dictionary, part: Dictionary) -> bool:
	for field: String in COUNTS:
		if int(total[field]) < int(part[field]):
			return false
	for column: String in EXPLOSIVE_COLUMNS:
		for field: String in WEAPON_COUNTS:
			if column_count(total, column, field) < column_count(part, column, field):
				return false
	if secrets(total) < secrets(part):
		return false
	for index: int in range(EquipmentState.WEAPONS.size()):
		for field: String in WEAPON_COUNTS:
			if weapon_count(total, index, field) < weapon_count(part, index, field):
				return false
	return true

static func secrets(counts: Dictionary) -> int:
	return int(counts.get("secrets", 0))

## A slot a five-slot record never sent counts as zero.
static func weapon_count(counts: Dictionary, index: int, field: String) -> int:
	var weapons: Array = counts["weapons"]
	return int(weapons[index][field]) if index < weapons.size() else 0

static func _valid_scope(data: Dictionary) -> bool:
	var scope: Variant = data.get("scope")
	if not scope is Dictionary:
		return false
	if scope.get("kind") in ["arena", "practice"]:
		return scope.size() == 2 and EquipmentState.integer(scope.get("round"), 4294967295) and scope.get("round") == data["round"] and data["attempt"] == data["total"]
	if scope.get("kind") != "mission" or scope.size() != 5 or scope.get("mission") not in [MissionState.ID, MissionState.M02_ID, MissionState.M03_ID, MissionState.M04_ID, MissionState.M05_ID, MissionState.M06_ID, MissionState.M07_ID, MissionState.M08_ID, MissionState.M09_ID, MissionState.M10_ID] \
		or not EquipmentState.integer(scope.get("attempt"), 4294967295) or int(scope["attempt"]) < 1 \
		or not MissionState.valid_rules(scope.get("rules"), 1) or not scope.has("run"):
		return false
	# Development records have no run. Durable solo records carry its identity.
	if scope["run"] == null:
		return true
	var run: Variant = scope["run"]
	# Historical service records retain the previous three-field run shape.
	if not MissionState.valid_run_identity(run, scope["attempt"], scope["mission"] == MissionState.ID):
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

static func column_count(counts: Dictionary, column: String, field: String) -> int:
	return int(counts.get(column, {}).get(field, 0))

static func grenade_count(counts: Dictionary, field: String) -> int:
	return column_count(counts, "grenades", field)

static func mine_count(counts: Dictionary, field: String) -> int:
	return column_count(counts, "mines", field)

static func remote_mine_count(counts: Dictionary, field: String) -> int:
	return column_count(counts, "remote_mines", field)

static func sum_combat(counts: Dictionary, field: String) -> int:
	return sum_weapon(counts, field) + grenade_count(counts, field) + mine_count(counts, field) + remote_mine_count(counts, field)
static func sum_weapon(counts: Dictionary, field: String) -> int:
	var total: int = 0
	for weapon: Dictionary in counts["weapons"]:
		total += int(weapon[field])
	return total

static func empty_counts() -> Dictionary:
	var counts: Dictionary = {"weapons": []}
	for field: String in COUNTS:
		counts[field] = 0
	for index: int in range(EquipmentState.WEAPONS.size()):
		var weapon: Dictionary = {}
		for field: String in WEAPON_COUNTS:
			weapon[field] = 0
		counts["weapons"].append(weapon)
	return counts

static func add_counts(total: Dictionary, value: Dictionary) -> void:
	for column: String in EXPLOSIVE_COLUMNS:
		if total.has(column) or value.has(column):
			var combined: Dictionary = {}
			for field: String in WEAPON_COUNTS:
				combined[field] = column_count(total, column, field) + column_count(value, column, field)
			total[column] = combined
	for field: String in COUNTS:
		total[field] = int(total[field]) + int(value[field])
	if secrets(total) + secrets(value) > 0:
		total["secrets"] = secrets(total) + secrets(value)
	for index: int in range(EquipmentState.WEAPONS.size()):
		for field: String in WEAPON_COUNTS:
			total["weapons"][index][field] = weapon_count(total, index, field) + weapon_count(value, index, field)
