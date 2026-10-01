class_name QaTurret
extends RefCounted

## QA observations only. Consecutive server ticks prove a covered charge ended
## early without its committed shot; this class never changes input or outcomes.
const CAMERA = preload("res://scripts/spectator_cam.gd")
const SIGHT_RANGE: float = 32.0
const CANCEL_TICKS: int = 12
const MAX_TRACE: int = 512

var _player_id: String = ""
var _target_name: String = ""
var _target_id: String = ""
var _solids: Array[Dictionary] = []
var _last_tick: int = -1
var _valid: bool = false
var _cycle: Dictionary = {}
var _trace: Array[Dictionary] = []
var _failures: Array[String] = []
var _cancellations: Array[Dictionary] = []

func begin(player_id: String, target_name: String, solids: Array) -> bool:
	_player_id = player_id
	_target_name = target_name
	_target_id = ""
	_last_tick = -1
	_cycle.clear()
	_trace.clear()
	_failures.clear()
	_cancellations.clear()
	_solids.clear()
	_valid = MissionState._uuid(player_id) and not target_name.is_empty() and target_name.length() <= 64 \
		and MapGeometry.validation_error({"geometry_version": 2, "map_id": 1, "half_extent": 256, "solids": solids}).is_empty()
	if _valid:
		_solids.assign(solids.duplicate(true))
	else:
		_fail("invalid observer identity or geometry")
	return _valid

func observe(snapshot: Dictionary) -> void:
	if not _valid:
		return
	if not EquipmentState.integer(snapshot.get("tick"), EquipmentState.MAX_EXACT_INTEGER):
		_invalid("invalid snapshot tick")
		return
	var tick: int = int(snapshot["tick"])
	if tick <= _last_tick:
		return
	if not _valid_snapshot(snapshot):
		_invalid("invalid actor or shot observation")
		return
	if _last_tick >= 0 and tick != _last_tick + 1:
		_fail("missing consecutive tick")
	_last_tick = tick
	var player: Dictionary = {}
	var target: Dictionary = {}
	var participants: int = 0
	for actor: Dictionary in snapshot["players"]:
		if ActorState.is_participant(actor):
			participants += 1
		if actor["id"] == _player_id:
			player = actor
		if actor["name"] == _target_name:
			if not target.is_empty():
				_invalid("ambiguous named actor")
				return
			target = actor
	if player.is_empty() or target.is_empty() or not ActorState.is_participant(player) \
		or not ActorState.is_union(target) or target["campaign"]["kind"] != "turret":
		_fail("registered living participant or Turret absent")
		return
	if _target_id.is_empty():
		_target_id = str(target["id"])
	elif _target_id != target["id"]:
		_invalid("registered Turret identity changed")
		return
	var identity: Dictionary = target["campaign"]
	var feet: Vector3 = _feet(player)
	var turret_feet: Vector3 = _feet(target)
	var in_range: bool = Vector2(feet.x - turret_feet.x, feet.z - turret_feet.z).length() <= SIGHT_RANGE
	var cover: Dictionary = _cover(turret_feet + Vector3(0, MoveStep.EYE_HEIGHT, 0), feet + Vector3(0, MoveStep.BODY_HEIGHT * 0.5, 0))
	var blocked: bool = not cover.is_empty()
	var shots: Array[Dictionary] = []
	for shot: Dictionary in snapshot.get("shot_results", []):
		if shot["shooter_id"] == _target_id:
			shots.append(shot.duplicate(true))
	var entry: Dictionary = {"tick": tick, "player_id": _player_id,
		"player_feet": [feet.x, feet.y, feet.z], "player_alive": int(player["hp"]) > 0,
		"turret_id": _target_id, "turret_name": _target_name,
		"turret_feet": [turret_feet.x, turret_feet.y, turret_feet.z],
		"turret_hp": int(target["hp"]), "phase": identity["phase"],
		"phase_started": int(identity["phase_started"]), "phase_ends": int(identity["phase_ends"]),
		"in_range": in_range, "cover_blocks_sight": blocked, "cover": cover, "shots": shots}
	if _trace.size() < MAX_TRACE:
		_trace.append(entry)
	else:
		_invalid("bounded observation trace exhausted")
		return
	if participants != 1 or int(player["hp"]) <= 0 or int(target["hp"]) <= 0:
		_fail("dead or ambiguous participant")
		return
	if not _cycle.is_empty():
		if not shots.is_empty():
			_fail("registered Turret fired during observed charge")
		elif int(target["hp"]) != int(_cycle["hp"]) or identity["phase"] in ["hit", "dead"]:
			_fail("damage or stagger interrupted charge")
	if _cycle.is_empty():
		# Starting exactly at phase_started prevents an unseen earlier interval
		# from standing in for an uninterrupted charge observation.
		if identity["phase"] == "windup" and int(identity["phase_started"]) == tick \
			and int(identity["phase_ends"]) > tick and not blocked and in_range and shots.is_empty():
			_cycle = {"started": tick, "deadline": int(identity["phase_ends"]),
				"hp": int(target["hp"]), "windup": entry.duplicate(true),
				"last_windup": entry.duplicate(true), "cancel": {}}
		return
	var cancelled: Dictionary = _cycle["cancel"]
	if cancelled.is_empty():
		if identity["phase"] == "windup" and int(identity["phase_started"]) == int(_cycle["started"]) \
			and int(identity["phase_ends"]) == int(_cycle["deadline"]):
			_cycle["last_windup"] = entry.duplicate(true)
			return
		# Enemy intent reads the prior snapshot before movement emits this tick.
		# Cover entered only on Recovery cannot establish why the charge ended.
		var before_cancel: Dictionary = _cycle["last_windup"]
		if int(before_cancel["tick"]) != tick - 1 or not before_cancel["cover_blocks_sight"] \
			or not before_cancel["in_range"] or not before_cancel["player_alive"] \
			or int(before_cancel["turret_hp"]) != int(_cycle["hp"]):
			_fail("prior deciding Windup does not prove living in-range cover")
			return
		if identity["phase"] != "recovery" or int(identity["phase_started"]) != tick \
			or int(identity["phase_ends"]) - tick != CANCEL_TICKS \
			or tick >= int(_cycle["deadline"]) or not blocked or not in_range:
			_fail("transition does not prove an early covered cancellation")
			return
		_cycle["cancel"] = entry.duplicate(true)
		_cycle["before_cancel"] = before_cancel.duplicate(true)
	elif tick > int(_cycle["deadline"]):
		if _cancellations.size() < 8:
			_cancellations.append({"turret_id": _target_id, "turret_name": _target_name,
				"windup": _cycle["windup"], "before_cancel": _cycle["before_cancel"], "cancel": cancelled,
				"verified_through_tick": tick, "original_deadline": _cycle["deadline"],
				"no_registered_shot": true, "turret_hp_unchanged": true})
		_cycle.clear()

func report() -> Dictionary:
	return {"passed": _valid and not _cancellations.is_empty(),
		"cancellations": _cancellations.duplicate(true), "failures": _failures.duplicate(),
		"trace": _trace.duplicate(true)}

func _fail(reason: String) -> void:
	_cycle.clear()
	if _failures.size() < 32 and reason not in _failures:
		_failures.append(reason)

func _invalid(reason: String) -> void:
	_fail(reason)
	_valid = false

static func _feet(actor: Dictionary) -> Vector3:
	return Vector3(float(actor["x"]), float(actor["y"]) - CAMERA.FP_SERVER_REFERENCE_Y, float(actor["z"]))

func _cover(from: Vector3, to: Vector3) -> Dictionary:
	for index: int in range(_solids.size()):
		var solid: Dictionary = _solids[index]
		var lower: Vector3 = Vector3(solid["min_x"], solid.get("bottom", 0.0), solid["min_z"])
		var upper: Vector3 = Vector3(solid["max_x"], solid["top"], solid["max_z"])
		if AABB(lower, upper - lower).intersects_segment(from, to) != null:
			return {"solid_index": index, "solid": solid.duplicate(true)}
	return {}

static func _valid_snapshot(snapshot: Dictionary) -> bool:
	var players: Variant = snapshot.get("players")
	var shots: Variant = snapshot.get("shot_results", [])
	if not players is Array or players.size() > 256 or not shots is Array or shots.size() > 512 \
		or not ActorState.validation_error(snapshot).is_empty():
		return false
	var ids: Dictionary[String, bool] = {}
	for actor: Variant in players:
		if not actor is Dictionary or not MissionState._uuid(actor.get("id")) \
			or ids.has(actor["id"]) or not actor.get("name") is String \
			or not MapGeometry._number(actor.get("hp")) or float(actor["hp"]) != floorf(float(actor["hp"])) \
			or float(actor["hp"]) < -2147483648.0 or float(actor["hp"]) > 2147483647.0:
			return false
		ids[actor["id"]] = true
		for axis: String in ["x", "y", "z"]:
			var coordinate: Variant = actor.get(axis)
			if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)) \
				or absf(float(coordinate)) > 512:
				return false
	for shot: Variant in shots:
		if not shot is Dictionary or not MissionState._uuid(shot.get("shooter_id")) \
			or not EquipmentState.integer(shot.get("damage"), 65535) \
			or not shot.get("hit") is bool or not shot.get("killed") is bool:
			return false
	return true
