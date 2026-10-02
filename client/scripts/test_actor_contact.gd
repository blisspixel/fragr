extends SceneTree

const FLAT: Dictionary = {"half": 40.0, "solids": []}
const FIELDS: Array[String] = ["x", "y", "z", "vx", "vy", "vz", "yaw"]
var _failures: Array[String] = []

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)

func _body(key: String, x: float, z: float, dx: float, dz: float) -> Dictionary:
	var body: Dictionary = ActorContact.stationary(key, Vector3(x, 0.0, z))
	body["proposed"]["x"] = x + dx
	body["proposed"]["z"] = z + dz
	body["proposed"]["vx"] = dx / MoveStep.DT_LIVE
	body["proposed"]["vz"] = dz / MoveStep.DT_LIVE
	return body

func _actor(id: String, hp: int = 100) -> Dictionary:
	return {"id": id, "x": 0.0, "y": 1.5, "z": 0.0, "hp": hp}

func _initialize() -> void:
	_goldens()
	_motion()
	_crowd_and_support()
	_boundaries()
	if _failures.is_empty():
		print("test_actor_contact: PASS (shared vectors, crowd, support and snapshot boundaries)")
	else:
		for failure: String in _failures:
			printerr("test_actor_contact: FAIL " + failure)
	quit(0 if _failures.is_empty() else 1)

func _goldens() -> void:
	var file: FileAccess = FileAccess.open("res://golden/actor_contact_vectors.json", FileAccess.READ)
	_check(file != null, "shared vectors load")
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	_check(parsed is Dictionary and parsed.get("version") == 1, "shared vectors version")
	if not parsed is Dictionary:
		return
	_check(absf(float(parsed["dt"]) - MoveStep.DT_LIVE) < 0.0000001, "shared live tick")
	for example: Dictionary in parsed["cases"]:
		var bodies: Array[Dictionary] = []
		for body: Dictionary in example["bodies"]:
			bodies.append(body)
		var result: Array[Dictionary] = ActorContact.resolve(bodies, float(parsed["dt"]), example["arena"])
		_check(result.size() == example["expected"].size(), "shared result count " + str(example["name"]))
		for index: int in range(result.size()):
			for field: String in FIELDS:
				_check(absf(float(result[index][field]) - float(example["expected"][index][field])) <= 0.0001,
					"shared %s[%d].%s" % [example["name"], index, field])
	for example: Dictionary in parsed["sweep_cases"]:
		var actual: float = ActorContact.sweep_time(example["a"], example["b"])
		_check(actual < 0.0 if example["expected"] == null else absf(actual - float(example["expected"])) <= 0.0001,
			"shared sweep " + str(example["name"]))

func _motion() -> void:
	var blocker: Dictionary = _body("b", 0.0, 0.0, 0.0, 0.0)
	var bodies: Array[Dictionary] = [_body("a", -1.2, 0.0, 0.3, 0.0), blocker]
	var result: Array[Dictionary] = ActorContact.resolve(bodies, MoveStep.DT_LIVE, FLAT)
	_check(absf(float(result[0]["x"]) + 1.0) <= 0.0001 and result[1] == blocker["from"], "stop without displacing a stationary body")
	_check(absf(float(result[0]["vx"]) - 4.0) <= 0.0001, "acknowledged velocity represents accepted distance")
	var mover: Dictionary = _body("a", -1.2, 0.0, 0.3, 0.2)
	for _tick: int in range(16):
		bodies = [mover, blocker]
		result = ActorContact.resolve(bodies, MoveStep.DT_LIVE, FLAT)
		_check(Vector2(float(result[0]["x"]), float(result[0]["z"])).length() >= 0.9999, "sustained glancing movement cannot penetrate")
		mover["from"] = result[0].duplicate()
		mover["proposed"] = result[0].duplicate()
		mover["proposed"]["x"] += 0.3
		mover["proposed"]["z"] += 0.2
	_check(float(result[0]["z"]) > 2.0, "sustained glancing controls make forward progress")
	bodies = [_body("a", -0.6, 0.0, 0.2, 0.1), _body("b", 0.6, 0.0, -0.2, -0.1)]
	result = ActorContact.resolve(bodies, MoveStep.DT_LIVE, FLAT)
	var reversed: Array[Dictionary] = [bodies[1], bodies[0]]
	var reverse_result: Array[Dictionary] = ActorContact.resolve(reversed, MoveStep.DT_LIVE, FLAT)
	_check(result[0] == reverse_result[1] and result[1] == reverse_result[0], "roster order cannot change deterministic contact results")
	var falling: Dictionary = _body("a", 0.5, 0.0, 0.25, 0.0)
	falling["from"]["y"] = 2.0
	falling["proposed"]["y"] = 1.5
	_check(ActorContact.sweep_time(falling, blocker) >= 0.0, "new vertical intersection is not mistaken for existing overlap escape")
	bodies = [falling]
	_check(ActorContact.resolve(bodies, NAN, FLAT)[0] == falling["from"], "invalid dt does not move bodies")

func _crowd_and_support() -> void:
	var bodies: Array[Dictionary] = []
	for index: int in range(32):
		bodies.append(_body("b%02d" % index, index * 1.001, 0.0, 0.25 if index < 31 else 0.0, 0.0))
	var distant: Dictionary = _body("z", 0.0, 10.0, 0.25, 0.0)
	bodies.append(distant)
	var result: Array[Dictionary] = ActorContact.resolve(bodies, MoveStep.DT_LIVE, FLAT)
	for i: int in range(result.size()):
		for j: int in range(i + 1, result.size()):
			_check(Vector2(float(result[i]["x"]) - float(result[j]["x"]), float(result[i]["z"]) - float(result[j]["z"])).length() >= 0.9999,
				"32-body propagation cannot leave a penetrating pair %d/%d" % [i, j])
	_check(result.back() == distant["proposed"], "crowded island does not freeze a distant mover")
	var world: Dictionary = {"half": 40.0, "solids": [{"min_x": -0.9, "max_x": 1.0, "min_z": -2.0, "max_z": 2.0, "bottom": 0.0, "top": 0.5}]}
	var climbing: Dictionary = _body("a", -1.1, 0.0, 0.25, 0.0)
	climbing["from"]["vx"] = 5.0
	climbing["proposed"] = MoveStep.integrate_with_height(climbing["from"], false, MoveStep.DT_LIVE, world, 1.8)
	_check(climbing["proposed"]["y"] == 0.5, "control actually reaches a stair")
	bodies = [climbing, _body("b", -0.05, 0.0, 0.0, 0.0)]
	result = ActorContact.resolve(bodies, MoveStep.DT_LIVE, world)
	_check(result[0]["y"] == 0.0 and float(result[0]["x"]) <= -1.0499, "blocked stair re-evaluates original support")
	world["solids"] = [{"min_x": -3.0, "max_x": -1.6, "min_z": -10.0, "max_z": 10.0, "bottom": 0.0, "top": 4.0}]
	bodies = [_body("a", -1.1, 0.0, 0.15, 0.2), _body("b", 0.0, 0.0, 0.0, 0.0)]
	result = ActorContact.resolve(bodies, MoveStep.DT_LIVE, world)
	_check(float(result[0]["z"]) > 0.1 and float(result[0]["x"]) >= -1.1001, "wall and body retain an open tangent route")

func _boundaries() -> void:
	var live: Dictionary = _actor("00000000-0000-0000-0000-000000000001")
	var detached: Dictionary = _actor("detached")
	detached["collidable"] = false
	var snapshot: Dictionary = {"tick": 12, "players": [live, _actor("dead", -20), detached]}
	var parsed: Dictionary = ActorContact.read_snapshot(snapshot)
	_check(parsed["error"] == "" and parsed["bodies"].size() == 1 and parsed["bodies"][0]["key"] == live["id"], "bare keys and explicit eligibility preserve legacy defaults and negative overkill")
	for value: Variant in [0, "true", null, []]:
		var bad: Dictionary = snapshot.duplicate(true)
		bad["players"][0]["collidable"] = value
		_check(not ActorContact.read_snapshot(bad)["error"].is_empty(), "reject nonboolean eligibility")
	for patch: Dictionary in [{"x": NAN}, {"hp": 1.5}, {"hp": 2147483648}, {"id": ""}, {"y": INF}]:
		var bad: Dictionary = snapshot.duplicate(true)
		bad["players"][0].merge(patch, true)
		_check(not ActorContact.read_snapshot(bad)["error"].is_empty(), "reject invalid body " + str(patch))
	var duplicate: Dictionary = snapshot.duplicate(true)
	duplicate["players"].append(live.duplicate())
	_check(not ActorContact.read_snapshot(duplicate)["error"].is_empty(), "reject duplicate body identity atomically")
	live["campaign"] = {"side": "participant"}
	var mission: Dictionary = {"phase": "in_progress", "party": [{"id": live["id"], "ready": false}], "run": {"status": "playing"}}
	_check(ActorContact.read_snapshot(snapshot, mission)["bodies"].is_empty(), "unready participant never blocks")
	mission["party"][0]["ready"] = true
	_check(ActorContact.read_snapshot(snapshot, mission)["bodies"].size() == 1, "ready participant blocks")
	mission["m02"] = {"evacuation": {"captives": [[1.0, 0.0, 2.0], [3.0, 0.0, 4.0]]}}
	mission["m03"] = {"cars": [{"id": "recall_a", "captives": [[5.0, 0.0, 6.0], [7.0, 0.0, 8.0]]}]}
	mission["m04"] = {"patients": [{"id": "patient_a", "feet": [9.0, 0.0, 10.0]}]}
	mission["m05"] = {"captives": [{"id": "worker_a", "feet": [11.0, 0.0, 12.0]}]}
	parsed = ActorContact.read_snapshot(snapshot, mission)
	var keys: Array[String] = []
	for body: Dictionary in parsed["bodies"]:
		keys.append(body["key"])
	_check(parsed["error"] == "" and keys == [str(live["id"]), "m02/captive/0", "m02/captive/1", "m03/recall_a/0", "m03/recall_a/1", "m04/patient_a", "m05/worker_a"], "civilian keys and feet mirror each mission owning boundary")
	mission["m05"]["captives"][0]["feet"][0] = INF
	_check(not ActorContact.read_snapshot(snapshot, mission)["error"].is_empty(), "invalid civilian feet reject the whole set")
	mission["phase"] = "briefing"
	_check(ActorContact.read_snapshot(snapshot, mission)["bodies"].is_empty(), "briefing removes player and civilian contacts")
	var crawler: Dictionary = _actor("crawler")
	crawler["campaign"] = {"side": "union", "kind": "crawler", "phase": "moving", "phase_started": 10, "phase_ends": 20}
	parsed = ActorContact.read_snapshot({"tick": 12, "players": [crawler]})
	_check(parsed["error"] == "" and parsed["bodies"][0]["height"] == 0.8, "Crawler uses authoritative short height")
	crawler["campaign"]["kind"] = "notary"
	parsed = ActorContact.read_snapshot({"tick": 12, "players": [crawler]})
	_check(parsed["error"] == "" and parsed["bodies"][0]["height"] == 0.7, "Notary uses authoritative hover height")
