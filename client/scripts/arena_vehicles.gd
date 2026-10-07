class_name ArenaVehicles
extends Node3D

## Bounded presentation only. Empty snapshots remove bodies, including wrecks.
var views: Dictionary[int, JeepView] = {}
var histories: Dictionary[int, RemotePresentation] = {}
var rows: Dictionary[int, Dictionary] = {}
var local_vehicle: int = 0
var last_tick: int = -1
var predicted_pose: Dictionary = {}

func reset() -> void:
	for view: JeepView in views.values():
		view.queue_free()
	views.clear()
	histories.clear()
	rows.clear()
	local_vehicle = 0
	last_tick = -1
	predicted_pose = {}

func apply(snapshot: Dictionary, player_id: String, now_usec: int) -> void:
	var tick: int = int(snapshot.get("tick", -1))
	if tick <= last_tick or not VehicleState.validation_error(snapshot).is_empty():
		return
	last_tick = tick
	var current: Dictionary[int, Dictionary] = {}
	var occupied: Dictionary = VehicleState.occupied(snapshot, player_id)
	local_vehicle = int(occupied["vehicle"]["id"]) if not occupied.is_empty() else 0
	predicted_pose = {}
	var actors: Dictionary = {}
	for actor: Dictionary in snapshot.get("players", []):
		actors[str(actor["id"])] = actor
	for row: Dictionary in snapshot.get("vehicles", []):
		var id: int = int(row["id"])
		var position_value: Vector3 = GrenadeFacts.vector(row["position"])
		if views.has(id) and views[id].kind != str(row["kind"]):
			views[id].queue_free()
			views.erase(id)
			histories.erase(id)
		if not views.has(id):
			var view: JeepView = JeepView.new()
			view.kind = str(row["kind"])
			view.name = "Jeep%d" % id
			add_child(view)
			view.position = position_value
			view.rotation.y = ServerYaw.pawn_rotation_y(float(row["yaw"]))
			views[id] = view
			histories[id] = RemotePresentation.new()
		current[id] = row.duplicate(true)
		histories[id].accept(tick, position_value, float(row["yaw"]), 0.0, int(row["hp"]) > 0, now_usec)
		if histories[id].discontinuity:
			views[id].position = position_value
		var gunner: Dictionary = actors.get(str(row["gunner"]), {})
		views[id].apply(row, float(gunner.get("yaw", row["yaw"])), float(gunner.get("pitch", 0.0)))
	for id: int in views.keys():
		if not current.has(id):
			views[id].queue_free()
			views.erase(id)
			histories.erase(id)
	rows = current

func shot(vehicle_id: int) -> void:
	if views.has(vehicle_id):
		views[vehicle_id].shot()

func _process(delta: float) -> void:
	var now_usec: int = Time.get_ticks_usec()
	for id: int in views:
		var view: JeepView = views[id]
		if id == local_vehicle:
			if not predicted_pose.is_empty():
				view.position = predicted_pose["position"]
				view.rotation.y = ServerYaw.pawn_rotation_y(float(predicted_pose["yaw"]))
				continue
			# Authoritative seat movement for the initial seam. The driver's
			# chassis follows the same 18/s camera blend, never remote buffering.
			view.position = view.position.lerp(GrenadeFacts.vector(rows[id]["position"]), minf(1.0, 18.0 * delta))
			view.rotation.y = lerp_angle(view.rotation.y, ServerYaw.pawn_rotation_y(float(rows[id]["yaw"])), minf(1.0, 18.0 * delta))
		else:
			var sample: Dictionary = histories[id].sample(now_usec)
			if not sample.is_empty():
				view.position = sample["position"]
				view.rotation.y = ServerYaw.pawn_rotation_y(float(sample["yaw"]))
