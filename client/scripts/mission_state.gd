class_name MissionState
extends RefCounted

## Mirror of protocol/mission.rs. Validation grants no local mission authority.
const ID: String = "recall_notice"
const M03_ID: String = "scheduled_service"
const M04_ID: String = "notice_to_vacate"
const M05_ID: String = "no_forwarding_address"
const DIFFICULTIES: Array[String] = ["assisted", "standard", "severe"]
## Revision 3 adds Notary timing. Revision 2 removed magazines and reloading.
## Records keep their earned revision; current live facts require revision 3.
const RULES_REVISION: int = 3
const PHASES: Array[String] = ["briefing", "find_transfer", "reach_lift", "departed"]
const RUN_STATUSES: Array[String] = ["playing", "continue", "failed", "complete", "abandoned"]
const INVALID: String = "The server sent invalid mission state. Connection closed."

static func map_error(info: Dictionary) -> String:
	if info.has("m05"):
		return M05MissionState.map_error(info)
	if info.has("m04"):
		return M04MissionState.map_error(info)
	if info.has("m03"):
		return M03MissionState.map_error(info)
	var m02_problem: String = m02_map_error(info)
	if not m02_problem.is_empty() or info.get("m02_objectives") != null:
		return m02_problem
	if info.has("m02_side_ward") and (not info["m02_side_ward"] is bool or info["m02_side_ward"]):
		return INVALID
	var value: Variant = info.get("mission")
	if value == null:
		return ""
	if not value is Dictionary or value.size() != 4 or value.get("id") != ID:
		return INVALID
	var presentation: Variant = info.get("presentation")
	if not presentation is Dictionary or not presentation.get("decorations") is Array:
		return INVALID
	var details: Array = presentation["decorations"]
	var boarding: Variant = value.get("boarding")
	var half: float = float(info["half_extent"])
	if not boarding is Dictionary or boarding.size() != 2 \
		or not _point(boarding.get("min"), half) or not _point(boarding.get("max"), half):
		return INVALID
	for axis: int in range(3):
		if float(boarding["min"][axis]) >= float(boarding["max"][axis]):
			return INVALID
	var indices: Array[int] = []
	for key: String in ["record", "departure"]:
		var control: Variant = value.get(key)
		if not control is Dictionary or control.size() != 2 or details.is_empty() \
			or not EquipmentState.integer(control.get("decoration"), details.size() - 1) \
			or not _point(control.get("approach"), half):
			return INVALID
		var index: int = int(control["decoration"])
		if index in indices or details[index]["kind"] != ("terminal" if key == "record" else "lift_control"):
			return INVALID
		indices.append(index)
		if key == "departure":
			for axis: int in range(3):
				if float(control["approach"][axis]) < float(boarding["min"][axis]) \
					or float(control["approach"][axis]) > float(boarding["max"][axis]):
					return INVALID
	return ""

static func validation_error(message: Dictionary, geometry: Dictionary, previous: Dictionary = {}) -> String:
	var claimed: Variant = message.get("state")
	if geometry.get("id") == M05_ID or (claimed is Dictionary and claimed.get("id") == M05_ID):
		return M05MissionState.validation_error(message, geometry, previous)
	if geometry.get("id") == M04_ID or (claimed is Dictionary and claimed.get("id") == M04_ID):
		return M04MissionState.validation_error(message, geometry, previous)
	if geometry.get("id") == M03_ID or (claimed is Dictionary and claimed.get("id") == M03_ID):
		return M03MissionState.validation_error(message, geometry, previous)
	if geometry.get("id") == M02_ID or (claimed is Dictionary and claimed.get("id") == M02_ID):
		return m02_validation_error(message, geometry, previous)
	var value: Variant = message.get("state")
	if not EquipmentState.integer(message.get("tick"), EquipmentState.MAX_EXACT_INTEGER) \
		or not value is Dictionary or value.size() != (8 if value.has("run") else 7) or geometry.get("id") != ID or value.get("id") != ID \
		or not valid_rules(value.get("rules")) \
		or not value.get("phase") is String or value["phase"] not in PHASES \
		or not EquipmentState.integer(value.get("attempt"), 4294967295) or int(value["attempt"]) == 0 \
		or not EquipmentState.integer(value.get("changed_at"), int(message["tick"])) \
		or not value.get("party") is Array or value["party"].size() > 4 \
		or not value.get("prompts") is Array or value["prompts"].size() > value["party"].size():
		return INVALID
	if value.has("run") and not valid_run(value):
		return INVALID
	if not previous.is_empty() and (int(value["attempt"]) < int(previous["state"]["attempt"]) \
		or int(message["tick"]) < int(previous["tick"]) or value["rules"] != previous["state"]["rules"] \
		or not run_follows(value.get("run"), previous["state"].get("run"))):
		return INVALID
	var party: Dictionary = {}
	var ready: bool = true
	for member: Variant in value["party"]:
		if not member is Dictionary or member.size() != 5 or not _uuid(member.get("id")) \
			or party.has(member["id"]) or not member.get("name") is String \
			or member["name"].is_empty() or member["name"].length() > 48 \
			or not member.get("ready") is bool or not member.get("alive") is bool or not member.get("aboard") is bool \
			or (member["aboard"] and (not member["alive"] or not member["ready"] or value["phase"] == "briefing")):
			return INVALID
		for character: String in member["name"]:
			var code: int = character.unicode_at(0)
			if code < 32 or (code >= 127 and code <= 159):
				return INVALID
		party[member["id"]] = member
		ready = ready and member["alive"] and member["aboard"]
	var prompted: Array[String] = []
	for prompt: Variant in value["prompts"]:
		if not prompt is Dictionary or prompt.size() != 2 or not _uuid(prompt.get("player_id")) \
			or not party.has(prompt["player_id"]) or not party[prompt["player_id"]]["alive"] \
			or not party[prompt["player_id"]]["ready"] \
			or prompt["player_id"] in prompted:
			return INVALID
		if (value["phase"] == "find_transfer" and prompt.get("kind") != "transfer_record") \
			or (value["phase"] == "reach_lift" and (prompt.get("kind") != "lift_departure" or not ready)) \
			or value["phase"] in ["briefing", "departed"]:
			return INVALID
		prompted.append(prompt["player_id"])
	return ""

static func valid_rules(value: Variant, oldest: int = RULES_REVISION) -> bool:
	return value is Dictionary and value.size() == 2 \
		and value.get("difficulty") is String and value["difficulty"] in DIFFICULTIES \
		and EquipmentState.integer(value.get("revision"), RULES_REVISION) and int(value["revision"]) >= maxi(oldest, 1)

static func valid_run_identity(run: Variant, attempt: Variant, allow_legacy: bool = false) -> bool:
	if not run is Dictionary or run.size() != (4 if run.has("level_start_continues") else 3) \
		or (not run.has("level_start_continues") and not allow_legacy) or not _uuid(run.get("id")) \
		or run["id"] == "00000000-0000-0000-0000-000000000000" \
		or not run.get("status") is String or run["status"] not in RUN_STATUSES \
		or not EquipmentState.integer(run.get("continues"), 3) \
		or (run.has("level_start_continues") and not EquipmentState.integer(run["level_start_continues"], 3)) \
		or int(run["continues"]) > int(run.get("level_start_continues", 3)) \
		or not EquipmentState.integer(attempt, 4) \
		or int(attempt) != int(run.get("level_start_continues", 3)) - int(run["continues"]) + 1:
		return false
	return not ((run["status"] == "continue" and run["continues"] == 0) \
		or (run["status"] == "failed" and run["continues"] != 0))

static func valid_run(state: Dictionary) -> bool:
	var run: Variant = state.get("run")
	if not valid_run_identity(run, state.get("attempt")) or state["party"].size() > 1:
		return false
	if state.get("id") == ID and int(run["level_start_continues"]) != 3:
		return false
	if (run["status"] == "complete") != (state["phase"] == "departed") \
		or (run["status"] == "abandoned" and not state["party"].is_empty()) \
		or (run["status"] != "playing" and not state["prompts"].is_empty()):
		return false
	if run["status"] == "failed" and state["party"].is_empty():
		return true
	if run["status"] in ["continue", "failed"]:
		return state["party"].size() == 1 and state["party"][0] is Dictionary and state["party"][0].get("alive") == false
	return true

static func run_follows(current: Variant, previous: Variant) -> bool:
	if previous == null or current == null:
		return previous == current
	return current["id"] == previous["id"] and current["continues"] <= previous["continues"] \
		and current.get("level_start_continues", 3) == previous.get("level_start_continues", 3)

static func _point(value: Variant, half: float) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for axis: int in range(3):
		if not (value[axis] is int or value[axis] is float) or not is_finite(float(value[axis])):
			return false
	return absf(float(value[0])) <= half and absf(float(value[2])) <= half \
		and float(value[1]) >= 0.0 and float(value[1]) <= MapGeometry.MAX_HALF * 2.0

static func _uuid(value: Variant) -> bool:
	if not value is String or value.length() != 36:
		return false
	for index: int in range(36):
		if index in [8, 13, 18, 23]:
			if value[index] != "-": return false
		elif value[index].to_lower() not in "0123456789abcdef":
			return false
	return true

## M02 mirrors the optional `m02` field of protocol/mission.rs. MapInfo binds
## the objective count and panels; mission state never names text or scripts.
const M02_ID: String = "persons_unknown"
const M02_PHASES: Array[String] = ["briefing", "in_progress", "departed"]
const M02_DEPARTURE: String = "party_departed"
const M02_MAX_OBJECTIVES: int = 8
const M02_EVAC_PHASES: Array[String] = ["held", "freeing", "ready", "moving", "waiting", "evacuated"]
const M02_HELD_FEET: Array[Vector3] = [Vector3(22.6, 0.0, 9.0), Vector3(24.5, 0.0, 9.0)]
const M02_WAIT_FEET: Array[Vector3] = [Vector3(-5.2, 0.0, 11.0), Vector3(-3.5, 0.0, 11.0)]
const M02_DOCK_SAFE_MIN: Vector2 = Vector2(-2.5, 19.0)
const M02_DOCK_SAFE_MAX: Vector2 = Vector2(4.0, 23.0)

static func m02_map_error(info: Dictionary) -> String:
	var count: Variant = info.get("m02_objectives")
	if count == null:
		return ""
	var presentation: Variant = info.get("presentation")
	if info.get("mission") != null or not EquipmentState.integer(count, M02_MAX_OBJECTIVES) or int(count) < 1 \
		or not info.get("m02_side_ward", false) is bool \
		or not presentation is Dictionary or not presentation.get("decorations") is Array:
		return INVALID
	return ""

## The validated contract a later mission message must match, or empty.
static func geometry_for(info: Dictionary) -> Dictionary:
	if info.has("m05"):
		return M05MissionState.geometry_for(info)
	if info.get("m04") is Dictionary:
		return M04MissionState.geometry_for(info)
	if info.get("m03") is Dictionary:
		return M03MissionState.geometry_for(info)
	if info.get("mission") is Dictionary:
		return info["mission"]
	if info.get("m02_objectives") == null:
		return {}
	var kinds: Array[String] = []
	for detail: Dictionary in info["presentation"]["decorations"]:
		kinds.append(str(detail["kind"]))
	return {"id": M02_ID, "map_id": int(info["map_id"]), "total": int(info["m02_objectives"]), "half_extent": float(info["half_extent"]),
		"kinds": kinds, "side_ward": bool(info.get("m02_side_ward", false))}

static func m02_validation_error(message: Dictionary, geometry: Dictionary, previous: Dictionary = {}) -> String:
	var value: Variant = message.get("state")
	if not EquipmentState.integer(message.get("tick"), EquipmentState.MAX_EXACT_INTEGER) \
		or not value is Dictionary or value.size() != (9 if value.has("run") else 8) \
		or geometry.get("id") != M02_ID or value.get("id") != M02_ID \
		or not valid_rules(value.get("rules")) \
		or not value.get("phase") is String or value["phase"] not in M02_PHASES \
		or not EquipmentState.integer(value.get("attempt"), 4294967295) or int(value["attempt"]) == 0 \
		or not EquipmentState.integer(value.get("changed_at"), int(message["tick"])) \
		or not value.get("party") is Array or value["party"].size() > 4 \
		or not value.get("prompts") is Array or value["prompts"].size() > value["party"].size() \
		or not value.get("m02") is Dictionary:
		return INVALID
	if value.has("run") and not valid_run(value):
		return INVALID
	var progress: Dictionary = value["m02"]
	var total: int = int(geometry["total"])
	if not progress.get("completed") is Array or not EquipmentState.integer(progress.get("total"), M02_MAX_OBJECTIVES) \
		or int(progress["total"]) != total or not EquipmentState.integer(progress.get("gate_mask"), 7) \
		or not progress.get("ward_secured") is bool or not progress.get("side_ward_secured") is bool \
		or progress.size() != ((7 if progress.has("current") else 6) if progress.has("evacuation") else (6 if progress.has("current") else 5)) \
		or progress.has("evacuation") != geometry.get("side_ward", false) \
		or (not progress.has("evacuation") and progress["side_ward_secured"]) \
		or (progress.has("evacuation") and not _m02_evacuation_valid(progress["evacuation"], progress, value["phase"], float(geometry["half_extent"]))):
		return INVALID
	var completed: Array = progress["completed"]
	var departed: bool = value["phase"] == "departed"
	var current: Variant = progress.get("current")
	if completed.size() > total or departed != (completed.size() == total) \
		or (current != null) != (completed.size() < total) \
		or (value["phase"] == "briefing" and (not completed.is_empty() or int(progress["gate_mask"]) != 0 \
			or progress["ward_secured"] or progress["side_ward_secured"])) \
		or (progress["side_ward_secured"] and not progress["ward_secured"]) \
		or ("companion_released" in completed and not progress["ward_secured"]):
		return INVALID
	var seen: Array[String] = []
	for id: Variant in completed:
		if not valid_objective_id(id) or id in seen:
			return INVALID
		seen.append(id)
	if seen.count(M02_DEPARTURE) != (1 if departed else 0) or (departed and seen.back() != M02_DEPARTURE):
		return INVALID
	var use_prompt: bool = false
	if current != null:
		var problem: String = _m02_objective_error(current, geometry, seen)
		if not problem.is_empty():
			return problem
		use_prompt = current["action"]["kind"] == "use" and value["phase"] == "in_progress"
		if current["id"] == "companion_released" and not progress["ward_secured"]:
			use_prompt = false
		if current["id"] == M02_DEPARTURE and (completed.size() + 1 != total or current["action"]["kind"] != "arrival"):
			return INVALID
	if not previous.is_empty():
		var old: Dictionary = previous["state"]
		if int(value["attempt"]) < int(old["attempt"]) or int(message["tick"]) < int(previous["tick"]) \
			or value["rules"] != old["rules"] or old.get("id") != M02_ID \
			or not run_follows(value.get("run"), old.get("run")):
			return INVALID
		# Within one attempt, progress only extends; a retry may restart it.
		if int(value["attempt"]) == int(old["attempt"]):
			var before: Array = old["m02"]["completed"]
			if completed.size() < before.size() or completed.slice(0, before.size()) != before \
				or (old["m02"]["ward_secured"] and not progress["ward_secured"]) \
				or (old["m02"]["side_ward_secured"] and not progress["side_ward_secured"]) \
				or progress.has("evacuation") != old["m02"].has("evacuation") \
				or (progress.has("evacuation") and not _m02_evacuation_follows(progress["evacuation"], old["m02"]["evacuation"], old["phase"])):
				return INVALID
	var party: Dictionary = {}
	for member: Variant in value["party"]:
		if not member is Dictionary or member.size() != 5 or not _uuid(member.get("id")) \
			or party.has(member["id"]) or not member.get("name") is String \
			or member["name"].is_empty() or member["name"].length() > 48 \
			or not member.get("ready") is bool or not member.get("alive") is bool or not member.get("aboard") is bool \
			or (member["aboard"] and (not member["alive"] or not member["ready"] or value["phase"] == "briefing")):
			return INVALID
		for character: String in member["name"]:
			var code: int = character.unicode_at(0)
			if code < 32 or (code >= 127 and code <= 159):
				return INVALID
		party[member["id"]] = member
	var prompted: Array[String] = []
	for prompt: Variant in value["prompts"]:
		if not use_prompt or not prompt is Dictionary or prompt.size() != 2 or not _uuid(prompt.get("player_id")) \
			or prompt.get("kind") != "objective_use" or not party.has(prompt["player_id"]) \
			or not party[prompt["player_id"]]["alive"] or not party[prompt["player_id"]]["ready"] \
			or prompt["player_id"] in prompted:
			return INVALID
		prompted.append(prompt["player_id"])
	return ""

static func _m02_evacuation_valid(value: Variant, progress: Dictionary, mission_phase: String, half: float) -> bool:
	if not value is Dictionary or value.size() != 3 or not value.get("phase") is String \
		or value["phase"] not in M02_EVAC_PHASES or not value.get("evacuated") is bool \
		or not value.get("captives") is Array or value["captives"].size() != 2:
		return false
	for index: int in range(2):
		var feet: Variant = value["captives"][index]
		if not _point(feet, half) or absf(float(feet[1])) > 0.001:
			return false
		if value["phase"] == "held" and Vector3(float(feet[0]), float(feet[1]), float(feet[2])).distance_to(M02_HELD_FEET[index]) > 0.01:
			return false
		if value["phase"] == "waiting" and Vector3(float(feet[0]), float(feet[1]), float(feet[2])).distance_to(M02_WAIT_FEET[index]) > 0.25:
			return false
	var phase: String = value["phase"]
	if phase == "evacuated":
		for feet: Array in value["captives"]:
			if float(feet[0]) < M02_DOCK_SAFE_MIN.x or float(feet[0]) > M02_DOCK_SAFE_MAX.x \
				or float(feet[2]) < M02_DOCK_SAFE_MIN.y or float(feet[2]) > M02_DOCK_SAFE_MAX.y:
				return false
	return value["evacuated"] == (phase == "evacuated") \
		and (progress["side_ward_secured"] or phase == "held") \
		and (mission_phase != "briefing" or phase == "held")

static func _m02_evacuation_follows(current: Dictionary, previous: Dictionary, old_mission_phase: String) -> bool:
	if old_mission_phase == "departed" or previous["phase"] == "evacuated":
		return current == previous
	if current["phase"] == previous["phase"]:
		return true
	# Mission changes use the reliable ordered WebSocket door. The server sends
	# every phase edge, including the wait-to-move restart, before new positions.
	match previous["phase"]:
		"held": return current["phase"] == "freeing"
		"freeing": return current["phase"] == "ready"
		"ready": return current["phase"] == "moving"
		"moving": return current["phase"] in ["waiting", "evacuated"]
		"waiting": return current["phase"] == "moving"
	return false

static func _m02_objective_error(current: Variant, geometry: Dictionary, completed: Array[String]) -> String:
	if not current is Dictionary or current.size() != 2 or not valid_objective_id(current.get("id")) \
		or current["id"] in completed or not current.get("action") is Dictionary:
		return INVALID
	var action: Dictionary = current["action"]
	var half: float = float(geometry["half_extent"])
	match action.get("kind"):
		"arrival":
			var region: Variant = action.get("region")
			if action.size() != 3 or not region is Dictionary or region.size() != 2 \
				or not _point(region.get("min"), half) or not _point(region.get("max"), half) \
				or not _point(action.get("feet"), half):
				return INVALID
			for axis: int in range(3):
				var low: float = float(region["min"][axis])
				var high: float = float(region["max"][axis])
				var foot: float = float(action["feet"][axis])
				if low >= high or foot < low or foot > high:
					return INVALID
		"use":
			var target: Variant = action.get("target")
			var kinds: Array = geometry["kinds"]
			if action.size() != 2 or not target is Dictionary or target.size() != 2 or kinds.is_empty() \
				or not EquipmentState.integer(target.get("decoration"), kinds.size() - 1) \
				or kinds[int(target["decoration"])] not in ["terminal", "lift_control"] \
				or not _point(target.get("approach"), half):
				return INVALID
		_:
			return INVALID
	return ""

static func valid_objective_id(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 64:
		return false
	for character: String in value:
		if character not in "abcdefghijklmnopqrstuvwxyz0123456789_":
			return false
	return true
