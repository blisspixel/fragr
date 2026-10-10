extends SceneTree

const SELF: String = "00000000-0000-0000-0000-000000000001"
const OTHER: String = "00000000-0000-0000-0000-000000000002"
var failures: Array[String] = []
var accepted: int = 0
var refused: int = 0

class WireProbe extends "res://scripts/net_client.gd":
	var captured: Dictionary = {}
	func send_json(message):
		captured = message

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

static func _jeep() -> Dictionary:
	return {"id": 1, "kind": "jeep", "position": [0.0, 0.0, 0.0], "yaw": 0.0,
		"speed": 0.0, "vy": 0.0, "hp": 400, "driver": null, "gunner": null, "gun_heat": 0.0, "burning_ticks": 0, "control_ready_tick": 0}

static func _snapshot(tick: int = 100) -> Dictionary:
	return {"type": "snapshot", "tick": tick, "round_state": "Active", "players": [
		{"id": SELF, "name": "Meat", "hp": 100, "x": 0.0, "y": 1.5, "z": 0.0},
		{"id": OTHER, "name": "Probe", "hp": 100, "x": 2.0, "y": 1.5, "z": 0.0}], "vehicles": [_jeep()]}

func _boundaries() -> void:
	var wire: WireProbe = WireProbe.new()
	wire.send_action({"seq": 1, "seat": "gunner", "fire": false})
	_check(wire.captured.get("seat") == "gunner", "seat request survives actual field-by-field Action serialization")
	wire.send_action({"seq": 2})
	_check(not wire.captured.has("seat"), "ordinary Action omits seat")
	wire.send_action({"seq": 3, "seat": "other"})
	_check(not wire.captured.has("seat"), "invalid local seat cannot reach wire")
	wire.free()
	_check(VehicleState.validation_error({}).is_empty(), "old snapshots may omit vehicles")
	_check(VehicleState.validation_error(_snapshot()).is_empty(), "empty registered jeep is valid")
	var cases: Array[Array] = [["id", 0], ["id", 1.5], ["kind", "tank"], ["position", [NAN, 0, 0]],
		["position", [0, 0]], ["yaw", INF], ["speed", 21], ["vy", NAN], ["hp", -1], ["hp", 401],
		["gun_heat", -0.1], ["gun_heat", 1.01], ["burning_ticks", 41], ["driver", "missing"], ["control_ready_tick", 111]]
	for bad: Array in cases:
		var snapshot: Dictionary = _snapshot()
		snapshot["vehicles"][0][bad[0]] = bad[1]
		_check(not VehicleState.validation_error(snapshot).is_empty(), "reject bad vehicle " + str(bad))
	for field: String in VehicleState.KEYS:
		var snapshot: Dictionary = _snapshot()
		snapshot["vehicles"][0].erase(field)
		_check(not VehicleState.validation_error(snapshot).is_empty(), "reject missing " + field)
	var snapshot: Dictionary = _snapshot()
	snapshot["vehicles"][0]["driver"] = SELF
	snapshot["vehicles"][0]["gunner"] = OTHER
	_check(VehicleState.validation_error(snapshot).is_empty(), "distinct live seats are valid")
	_check(VehicleState.occupied(snapshot, SELF)["seat"] == "driver", "driver identified from authority")
	snapshot["vehicles"][0]["gunner"] = SELF
	_check(not VehicleState.validation_error(snapshot).is_empty(), "one actor cannot occupy two seats")
	snapshot["vehicles"][0]["gunner"] = null
	var second: Dictionary = _jeep()
	second["id"] = 2
	second["driver"] = SELF
	snapshot["vehicles"].append(second)
	_check(not VehicleState.validation_error(snapshot).is_empty(), "one actor cannot occupy two vehicles")
	snapshot["vehicles"].pop_back()
	snapshot["players"][0]["hp"] = 0
	_check(not VehicleState.validation_error(snapshot).is_empty(), "dead occupant rejected")
	snapshot["players"][0]["hp"] = NAN
	_check(not VehicleState.validation_error(snapshot).is_empty(), "nonfinite occupant health rejected")
	snapshot = _snapshot()
	snapshot["vehicles"][0]["hp"] = 0
	snapshot["vehicles"][0]["burning_ticks"] = 40
	_check(VehicleState.validation_error(snapshot).is_empty(), "burning destroyed jeep is valid")
	snapshot["vehicles"][0]["burning_ticks"] = 0
	_check(VehicleState.validation_error(snapshot).is_empty(), "retained wreck is valid")
	snapshot["shot_results"] = [{"trace": {"vehicle_id": 1, "weapon": "flechette"}}]
	snapshot["vehicles"] = []
	_check(VehicleState.validation_error(snapshot).is_empty(), "resolved mounted source survives removal of vehicle")
	snapshot["shot_results"][0]["trace"]["vehicle_id"] = 0
	_check(not VehicleState.validation_error(snapshot).is_empty(), "invalid mounted source refused even without vehicle list")
	snapshot = _snapshot()
	_check(VehicleState.nearby(snapshot, Vector3(1.9, 0, 0))["seat"] == "driver", "entry offers driver first")
	snapshot["vehicles"][0]["driver"] = SELF
	_check(VehicleState.nearby(snapshot, Vector3.ZERO)["seat"] == "gunner", "entry offers remaining gunner seat")
	snapshot["vehicles"][0]["speed"] = 2.01
	_check(VehicleState.nearby(snapshot, Vector3.ZERO).is_empty(), "moving vehicle cannot advertise entry")
	snapshot = _snapshot()
	snapshot["vehicles"][0]["kind"] = "light_aircraft"
	snapshot["vehicles"][0]["speed"] = 32.0
	_check(VehicleState.validation_error(snapshot).is_empty(), "registered aircraft accepts its flight speed")
	snapshot["vehicles"][0]["gunner"] = OTHER
	_check(not VehicleState.validation_error(snapshot).is_empty(), "single-seat aircraft rejects gunner")
	snapshot["vehicles"][0]["gunner"] = null
	snapshot["vehicles"][0]["driver"] = SELF
	snapshot["vehicles"][0]["speed"] = 0.0
	_check(VehicleState.nearby(snapshot, Vector3.ZERO).is_empty(), "occupied single-seat aircraft never offers gunner")
	snapshot["vehicles"][0]["driver"] = null
	_check(not VehicleState.nearby(snapshot, Vector3(0, 0, 5.9)).is_empty(), "aircraft prompt reaches beyond registered wing hull")
	_check(VehicleState.nearby(snapshot, Vector3(0, 0, 6.1)).is_empty(), "aircraft prompt stops at native six metre entry bound")
	var network: Node = load("res://scripts/net_client.gd").new()
	network.snapshot_received.connect(func(_data: Dictionary) -> void: accepted += 1)
	network.server_error.connect(func(_message: String) -> void: refused += 1)
	network._handle_message(JSON.stringify(_snapshot()))
	_check(accepted == 1 and refused == 0, "real wire boundary delivers good vehicle")
	var invalid: Dictionary = _snapshot()
	invalid["vehicles"][0]["gun_heat"] = 2
	network._handle_message(JSON.stringify(invalid))
	_check(accepted == 1 and refused == 1, "real wire boundary refuses malformed vehicle before presentation")
	network.free()

func _presentation() -> void:
	var world: ArenaVehicles = ArenaVehicles.new()
	root.add_child(world)
	var snapshot: Dictionary = _snapshot()
	world.apply(snapshot, SELF, 1000000)
	_check(world.views.size() == 1 and world.views[1].gun != null, "registered vehicle builds one world rig")
	world.shot(1)
	_check(world.views[1]._flash_left > 0.0, "resolved mounted source lights actual mounted gun")
	world.apply(snapshot, SELF, 1000100)
	_check(world.views.size() == 1, "duplicate snapshot cannot duplicate rig")
	snapshot["tick"] = 101
	snapshot["vehicles"][0]["driver"] = SELF
	snapshot["vehicles"][0]["position"] = [2.0, 0.0, 0.0]
	world.apply(snapshot, SELF, 1050000)
	_check(world.local_vehicle == 1, "driven vehicle avoids delayed remote buffer")
	world.predicted_pose = {"position": Vector3(2.2, 0, 0), "yaw": 0.2}
	world._process(0.016)
	_check(world.views[1].position == Vector3(2.2, 0, 0), "bounded local prediction drives chassis presentation")
	var hud: VehicleHud = VehicleHud.new()
	root.add_child(hud)
	hud.apply(snapshot, SELF, true)
	_check(hud.visible and hud.seat == "driver" and hud.summary.contains("HULL 400") and hud.prompt_text.contains("GUNNER"), "driver reads actual hull and seat controls")
	snapshot["tick"] = 102
	snapshot["vehicles"][0]["driver"] = null
	snapshot["vehicles"][0]["gunner"] = SELF
	snapshot["vehicles"][0]["gun_heat"] = 1.0
	hud.apply(snapshot, SELF, true)
	_check(hud.seat == "gunner" and hud.prompt_text.contains("GUN HOT"), "gunner sees heat recovery")
	hud.apply(snapshot, SELF, false)
	_check(not hud.visible, "spectator or blocked view hides local vehicle controls")
	snapshot["tick"] = 103
	snapshot["vehicles"] = []
	world.apply(snapshot, SELF, 1150000)
	_check(world.views.is_empty() and world.histories.is_empty(), "absent vehicle removes its interpolation history and node")
	world.reset()
	hud.queue_free()
	world.queue_free()

func _prediction() -> void:
	_check(VehicleStep.seat_feet(Vector3.ZERO, 0.0, "driver", "light_aircraft").is_equal_approx(Vector3(1.45, 0.8, 0.0)), "pilot seat is centered under the authored clear windscreen")
	var predict: VehiclePrediction = VehiclePrediction.new()
	predict.configure_map({"map_id": 7, "geometry_version": 2, "half_extent": 64.0, "solids": []})
	var snapshot: Dictionary = _snapshot()
	snapshot["players"][1]["x"] = 20.0
	snapshot["vehicles"][0]["driver"] = SELF
	predict.accept_vehicles(snapshot, SELF)
	var ack: Dictionary = {"seq": 0, "tick": 100, "movement": {"version": 1, "epoch": 1}}
	predict.accept_driver_ack(ack, 1000000)
	_check(predict.active(), "paired vehicle body and ACK activate shared bounded replay")
	var action: Dictionary = {"seq": 1, "forward": true, "back": false, "left": false, "right": false, "jump": false, "yaw": 1.5}
	predict.record_driver_action(action, 1000000, true)
	_check(predict.state["x"] > 0.0 and absf(predict.state["z"]) < 0.00001, "free-look yaw cannot steer the vehicle")
	var stepped: Dictionary = VehicleStep.step({"position": [0.0, 0.0, 0.0], "yaw": 0.0, "speed": 0.0, "vy": 0.0}, action, 0.05, predict.arena)
	snapshot["tick"] = 101
	for key: String in ["position", "yaw", "speed", "vy"]:
		snapshot["vehicles"][0][key] = stepped[key]
	predict.accept_vehicles(snapshot, SELF)
	ack["seq"] = 1
	ack["tick"] = 101
	predict.accept_driver_ack(ack, 1050000)
	_check(predict.correction_count == 1 and predict.correction_max < 0.0001, "same-tick replay measures zero drift for exact kernel input")
	var blockers: Array[Dictionary] = VehiclePrediction._blockers(snapshot, 1)
	_check(blockers.size() == 1 and float(blockers[0]["min_x"]) == 19.5, "driver excluded while unseated actors block vehicle replay")
	snapshot["vehicles"][0]["control_ready_tick"] = 110
	predict.accept_vehicles(snapshot, SELF)
	var still: Dictionary = {"x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.0, "vx": 0.0, "vz": 0.0, "vy": 0.0}
	var locked: Dictionary = predict._step(still, {"tick": 109, "input": action})
	var released: Dictionary = predict._step(still, {"tick": 110, "input": action})
	_check(locked["x"] == 0.0 and float(released["x"]) > 0.0, "seat switch starts exactly at server ready tick")
	var sample: Dictionary = predict._sample_action({"seq": 1, "forward": true, "back": false, "left": false, "right": false, "jump": false, "duck": true, "descend": true, "yaw": 0.0})
	_check(sample["descend"] and sample["duck"], "shared replay history retains independent climb and descend bits")
	var before: Dictionary = predict.state.duplicate()
	action["seq"] = 2
	predict.record_driver_action(action, 1050000, false)
	_check(predict.state == before, "failed driver send cannot move presentation")
	predict.advance(2000000)
	_check(not predict.active(), "late ACK stops driver speculation at shared bound")
	snapshot["vehicles"][0]["driver"] = null
	predict.accept_vehicles(snapshot, SELF)
	_check(predict.vehicle_id == 0 and predict.vehicle_samples.is_empty(), "exit clears vehicle replay and pair history")

func _run() -> void:
	root.set_meta("fragr_automated", true)
	_boundaries()
	_presentation()
	_prediction()
	await process_frame
	for failure: String in failures:
		push_error("test_vehicle_state: " + failure)
	if failures.is_empty():
		print("test_vehicle_state: PASS strict wire facts, seats, mounted evidence, presentation lifecycle and bounded driver replay")
	quit(0 if failures.is_empty() else 1)
