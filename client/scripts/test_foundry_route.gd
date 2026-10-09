extends SceneTree

## Direct shared-movement check of the authored QA route, without enemy intent.
func _initialize() -> void:
	set_meta("fragr_automated", true)
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../server/maps/test/m13_foundry_development.json"))
	var tour: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://qa/m13-foundry-development.json"))
	var solids: Array = []
	for row: Dictionary in source.solids:
		solids.append({"min_x":row.min[0],"max_x":row.max[0],"min_z":row.min[2],"max_z":row.max[2],"bottom":row.min[1],"top":row.max[1]})
	var world: Dictionary = {"half":source.half_extent,"solids":solids}
	var spawn: Array = source.spawns[0].feet
	var state: Dictionary = MoveStep.make_state(spawn[0],spawn[2],source.spawns[0].yaw)
	state.y = spawn[1]
	var count: int = 0
	var before_gallery: bool = true
	for capture: Dictionary in tour.states:
		if capture.name == "m13_ladle_galleries": before_gallery = false
		for goal: Array in capture.get("walk_to",[]):
			var arrived: bool = false
			for tick: int in range(1800):
				if Vector2(state.x-goal[0],state.z-goal[2]).length()<0.28 and absf(state.y-goal[1])<0.04:
					arrived=true
					break
				var yaw: float = atan2(goal[2]-state.z,goal[0]-state.x)
				state=MoveStep.live_step(state,MoveStep.make_input(true,false,false,false,yaw),MoveStep.TOP_SPEED,MoveStep.DT_LIVE,world)
				assert(not before_gallery or state.z<27.0,"QA approach crossed final activation before explicit gallery push")
			if not arrived:
				push_error("Blocked foundry QA segment in %s toward %s at %s" % [capture.name,goal,state])
				quit(1)
				return
			count+=1
	print("test_foundry_route: PASS %d ordinary shared-mirror waypoints, both stairs and pre-final exclusion" % count)
	quit(0)
