extends SceneTree

const Fixture = preload("res://scripts/test_local_prediction.gd")
const Vehicles = preload("res://scripts/test_vehicle_state.gd")
var failures: Array[String] = []

func _check(ok: bool, reason: String) -> void:
	if not ok:
		failures.append(reason)

func _initialize() -> void:
	var vehicle: Dictionary = Vehicles._jeep()
	vehicle.position = [2.5, 0.0, 0.0]
	vehicle.driver = Fixture.PEER_ID
	var snapshot: Dictionary = {"tick": 100, "players": [
		{"id": Fixture.LOCAL_ID, "x": 0.0, "y": 1.5, "z": 0.0, "hp": 100},
		{"id": Fixture.PEER_ID, "x": 8.0, "y": 1.5, "z": 0.0, "hp": 100, "collidable": true}], "vehicles": [vehicle]}
	var contacts: Dictionary = ActorContact.read_snapshot(snapshot)
	_check(contacts.error.is_empty() and contacts.bodies.size() == 1, "occupied actor is excluded even from an older collidable=true snapshot")
	var malformed: Dictionary = snapshot.duplicate(true)
	malformed.vehicles[0].position = [NAN, 0, 0]
	_check(not ActorContact.read_snapshot(malformed).error.is_empty(), "malformed vehicle cannot become a speculative hull")
	var crouched: Dictionary = snapshot.duplicate(true)
	crouched.vehicles = []
	crouched.players[1].ducking = true
	_check(ActorContact.read_snapshot(crouched).bodies[1].height == MoveStep.DUCK_HEIGHT, "standing walkers do not inherit a seated actor and crouched height is retained")

	var helpers: SceneTree = Fixture.new()
	var predictor: LocalPrediction = LocalPrediction.new()
	predictor.configure_map({"map_id": 7, "geometry_version": 2, "half_extent": 20.0, "solids": []})
	predictor.accept_ack(helpers._ack(0, 100), 1000000)
	predictor.accept_snapshot(snapshot, Fixture.LOCAL_ID, {}, 1000000)
	predictor.record_action(helpers._action(1), 1000001, true)
	_check(float(predictor.state.x) <= 0.1001 and float(predictor.state.x) >= 0.0, "ordinary pawn replay stops outside the registered jeep hull")
	predictor.advance(1050000)
	var old_hull: Dictionary = predictor.steps[0].vehicle_hulls[0].duplicate()
	vehicle.position[0] = 9.0
	snapshot.tick = 101
	predictor.accept_snapshot(snapshot, Fixture.LOCAL_ID, {}, 1050000)
	predictor.accept_ack(helpers._ack(1, 101, 1, 0.1), 1050001)
	_check(absf(float(predictor.state.x) - 0.1) < 0.001 and predictor.steps[0].vehicle_hulls[0] == old_hull, "a moved hull cannot rewrite an already retained input step")
	predictor.advance(1100000)
	_check(absf(float(predictor.state.x) - 0.35) < 0.001, "a new input step uses the new authoritative hull position")
	_check(predictor.arena.solids.is_empty(), "transient hulls never mutate the retained map geometry")

	var world: Dictionary = {"half": 20.0, "solids": [], "water_regions": [{"min": [-10.0, -10.0], "max": [10.0, 10.0], "level": 2.2, "depth": 2.2}]}
	var swimmer: Dictionary = MoveStep.make_state(0.0, 0.0, 0.0)
	swimmer.y = 1.3
	var contact: Dictionary = ActorContact.stationary(Fixture.PEER_ID, Vector3(1.1, 1.3, 0))
	var step: Dictionary = {"input": helpers._action(2), "speed": 5.0, "body_key": Fixture.LOCAL_ID, "blockers": [contact]}
	var moved: Dictionary = LocalPrediction._contact_step(swimmer, step, world)
	_check(absf(float(moved.x) - 0.1) < 0.001, "swimming contact still stops at another living body")
	_check(absf(float(moved.y) - 1.3) < 0.0001 and absf(float(moved.vy)) < 0.0001, "contact reprojection preserves the native buoyant support plane")
	_check(world.solids.is_empty(), "water support does not mutate shot or map geometry")
	helpers.free()
	for problem: String in failures:
		push_error("test_vehicle_contact_world: " + problem)
	print("test_vehicle_contact_world: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
