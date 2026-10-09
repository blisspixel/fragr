extends SceneTree

## Static QA authoring gate. Live combat and actual renderer checks stay separate.

func _initialize() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../server/maps/test/launch_authority_development.json"))
	var tour: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://qa/launch_authority_development.json"))
	var final_region: Dictionary = source.encounters[4].regions[0]
	var resupply: Dictionary = tour.states[13]
	assert(resupply.name == "launch_apron_resupply" and resupply.combat_travel == false)
	assert(tour.states[14].name == "launch_gantry_defense" and tour.states[14].walk_to.size() > 0)
	for pad: Dictionary in source.supplies:
		if str(pad.id).begins_with("apron_"):
			assert(not _contains(final_region, Vector3(pad.feet[0], pad.feet[1], pad.feet[2])))
	var solids: Array = []
	for row: Dictionary in source.solids:
		solids.append({"min_x": row.min[0], "max_x": row.max[0], "min_z": row.min[2], "max_z": row.max[2], "bottom": row.min[1], "top": row.max[1]})
	for vehicle: Dictionary in source.vehicles:
		solids.append(VehicleState.hull({"kind": "jeep", "position": vehicle.feet, "yaw": vehicle.yaw}))
	var world: Dictionary = {"half": source.half_extent, "solids": solids}
	var spawn: Array = source.spawns[0].feet
	var state: Dictionary = MoveStep.make_state(spawn[0], spawn[2], source.spawns[0].yaw)
	state.y = spawn[1]
	var count: int = 0
	for capture: Dictionary in tour.states:
		for goal: Array in capture.get("walk_to", []):
			var arrived: bool = false
			for tick: int in range(1800):
				if Vector2(state.x - goal[0], state.z - goal[2]).length() < 0.28 and absf(state.y - goal[1]) < 0.35:
					arrived = true
					break
				var yaw: float = atan2(goal[2] - state.z, goal[0] - state.x)
				state = MoveStep.live_step(state, MoveStep.make_input(true, false, false, false, yaw), MoveStep.TOP_SPEED, MoveStep.DT_LIVE, world)
				if capture.name == "launch_apron_resupply":
					assert(not _contains(final_region, Vector3(state.x, state.y, state.z)), "Pre-final resupply crossed gantry activation")
			if not arrived:
				push_error("Blocked direct QA segment in %s toward %s at %s" % [capture.name, goal, state])
				quit(1)
				return
			count += 1
	print("test_launch_authority_route: PASS %d ordinary shared-mirror waypoints with parked hull" % count)
	quit(0)

func _contains(region: Dictionary, point: Vector3) -> bool:
	return point.x >= region.min[0] and point.x <= region.max[0] and point.y >= region.min[1] and point.y <= region.max[1] and point.z >= region.min[2] and point.z <= region.max[2]
