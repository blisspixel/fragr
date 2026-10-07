class_name VehiclePrediction
extends LocalPrediction

## Reuse the existing bounded input history, tick pacing and correction blend.
## A same-tick vehicle snapshot supplies the body; its following ordinary ACK
## supplies the actually consumed input sequence. Pawn ACKs stay unmodified.
var vehicle_id: int = 0
var vehicle_kind: String = ""
var vehicle_samples: Dictionary[int, Dictionary] = {}
var world_samples: Dictionary[int, Dictionary] = {}
var water_regions: Array = []

func configure_map(info: Dictionary) -> void:
	super.configure_map(info)
	water_regions = info.get("water_regions", []).duplicate(true)

func reset_vehicle(reason: String) -> void:
	reset(reason)
	vehicle_id = 0
	vehicle_kind = ""
	vehicle_samples.clear()
	world_samples.clear()

func accept_vehicles(snapshot: Dictionary, player_id: String) -> void:
	var occupied: Dictionary = VehicleState.occupied(snapshot, player_id)
	if occupied.is_empty() or occupied["seat"] != "driver" or int(occupied["vehicle"]["hp"]) <= 0:
		reset_vehicle("not_driver")
		return
	var row: Dictionary = occupied["vehicle"]
	var identity: int = int(row["id"])
	if identity != vehicle_id or row["kind"] != vehicle_kind:
		reset_vehicle("vehicle_changed")
		vehicle_id = identity
		vehicle_kind = str(row["kind"])
	vehicle_samples[int(snapshot["tick"])] = row.duplicate(true)
	world_samples[int(snapshot["tick"])] = {"solids": _blockers(snapshot, identity), "ready_tick": row["control_ready_tick"]}
	while vehicle_samples.size() > 8:
		vehicle_samples.erase(vehicle_samples.keys()[0])
	while world_samples.size() > 8:
		world_samples.erase(world_samples.keys()[0])

func accept_driver_ack(ack: Dictionary, now_usec: int) -> void:
	var incoming_tick: int = int(ack.get("tick", -1))
	if vehicle_id == 0 or not vehicle_samples.has(incoming_tick) or not MovementAck.has_replay_body(ack):
		reset("missing_vehicle_ack_pair")
		return
	var row: Dictionary = vehicle_samples[incoming_tick]
	var position: Vector3 = GrenadeFacts.vector(row["position"])
	var yaw: float = float(row["yaw"])
	var speed: float = float(row["speed"])
	# Internal projection into the shared replay structure. This is never sent
	# or accepted as a pawn ACK and grants no authority to the predicted body.
	var body: Dictionary = {"seq": ack["seq"], "tick": incoming_tick,
		"x": position.x, "z": position.z, "yaw": yaw,
		"movement": {"version": 1, "epoch": ack["movement"]["epoch"], "applied": true,
			"y": position.y + FLOOR_OFFSET, "vx": cos(yaw) * speed, "vz": sin(yaw) * speed,
			"vy": row["vy"], "effective_speed": absf(speed), "jump_input": false}}
	accept_ack(body, now_usec)
	for sample_tick: int in vehicle_samples.keys():
		if sample_tick <= incoming_tick:
			vehicle_samples.erase(sample_tick)

func record_driver_action(action: Dictionary, now_usec: int, sent: bool) -> void:
	var controls: Dictionary = action.duplicate()
	controls["descend"] = bool(action.get("duck", false))
	# Brake is a held vehicle input, not the pawn's rising-edge jump latch.
	# The shared history already retains the held duck bit; only this internal
	# projection uses that slot for brake, and neither field changes on wire.
	controls["duck"] = bool(action.get("jump", false))
	controls["jump"] = false
	record_action(controls, now_usec, sent)

func _sample_action(action: Dictionary) -> Dictionary:
	var sample: Dictionary = super._sample_action(action)
	sample["descend"] = bool(action.get("descend", false))
	return sample

func _step(pose: Dictionary, step_record: Dictionary, delta: float = -1.0) -> Dictionary:
	var yaw: float = float(pose["yaw"])
	var motor: Dictionary = {"position": [pose["x"], pose["y"], pose["z"]], "yaw": yaw,
		"speed": float(pose["vx"]) * cos(yaw) + float(pose["vz"]) * sin(yaw), "vy": pose["vy"]}
	var input: Dictionary = step_record["input"].duplicate()
	input["brake"] = bool(input.get("duck", false))
	if not step_record.has("vehicle_world"):
		var sample: Dictionary = {}
		for sample_tick: int in world_samples:
			if sample_tick <= int(step_record["tick"]):
				sample = world_samples[sample_tick]
		step_record["vehicle_world"] = sample.duplicate(true)
	var world_sample: Dictionary = step_record["vehicle_world"]
	if int(step_record["tick"]) < int(world_sample.get("ready_tick", 0)):
		input = {}
	var world: Dictionary = arena.duplicate(true)
	world["solids"].append_array(world_sample.get("solids", []))
	var result: Dictionary = VehicleMediumStep.step(vehicle_kind, motor, input, delta if delta > 0.0 else MoveStep.DT_LIVE, world, water_regions)
	var position: Vector3 = GrenadeFacts.vector(result["position"])
	var facing: float = float(result["yaw"])
	var speed: float = float(result["speed"])
	return {"x": position.x, "y": position.y, "z": position.z, "yaw": facing,
		"vx": cos(facing) * speed, "vz": sin(facing) * speed, "vy": result["vy"]}

func presented_motion(now_usec: int) -> Dictionary:
	if not active():
		return {}
	var position: Vector3 = presented_position(now_usec) - Vector3(0, FLOOR_OFFSET, 0)
	var pose: Dictionary = _visual_pose if not _visual_pose.is_empty() else state
	return {"position": position, "yaw": float(pose["yaw"])}

static func _blockers(snapshot: Dictionary, identity: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var occupants: Dictionary = {}
	for vehicle: Dictionary in snapshot.get("vehicles", []):
		for seat: String in VehicleState.SEATS:
			if vehicle[seat] != null:
				occupants[vehicle[seat]] = true
		if int(vehicle["id"]) == identity:
			continue
		result.append(VehicleState.hull(vehicle))
	for actor: Dictionary in snapshot.get("players", []):
		if occupants.has(actor.get("id")) or float(actor.get("hp", 0)) <= 0.0 or not actor.get("collidable", true):
			continue
		var height: float = MoveStep.DUCK_HEIGHT if actor.get("ducking", false) else MoveStep.BODY_HEIGHT
		if ActorState.is_union(actor):
			if actor["campaign"]["kind"] == "crawler":
				height = 0.8
			elif actor["campaign"]["kind"] == "notary":
				height = 0.7
		var x: float = float(actor["x"])
		var z: float = float(actor["z"])
		var y: float = float(actor["y"]) - FLOOR_OFFSET
		result.append({"min_x": x - MoveStep.RADIUS, "max_x": x + MoveStep.RADIUS,
			"min_z": z - MoveStep.RADIUS, "max_z": z + MoveStep.RADIUS, "bottom": y, "top": y + height})
	return result
