extends SceneTree

## Check the exact authored lesson route with the shared movement mirror.
func _initialize() -> void:
	set_meta("fragr_automated", true)
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../server/maps/test/arc_foundation_development.json"))
	var tour: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://qa/arc-foundation-development.json"))
	var solids: Array = []
	for row: Dictionary in source.solids:
		solids.append({"min_x":row.min[0],"max_x":row.max[0],"min_z":row.min[2],"max_z":row.max[2],"bottom":row.min[1],"top":row.max[1]})
	var world: Dictionary = {"half":source.half_extent,"solids":solids}
	var spawn: Array = source.spawns[0].feet
	var state: Dictionary = MoveStep.make_state(spawn[0],spawn[2],source.spawns[0].yaw)
	state.y = spawn[1]
	var count: int = 0
	var before_final: bool = true
	for capture: Dictionary in tour.states:
		if capture.name == "arc_final_armor":
			before_final = false
		for goal: Array in capture.get("walk_to",[]):
			var arrived: bool = false
			for tick: int in range(1800):
				if Vector2(state.x-goal[0],state.z-goal[2]).length()<0.28 and absf(state.y-goal[1])<0.04:
					arrived=true
					break
				var yaw: float = atan2(goal[2]-state.z,goal[0]-state.x)
				state=MoveStep.live_step(state,MoveStep.make_input(true,false,false,false,yaw),MoveStep.TOP_SPEED,MoveStep.DT_LIVE,world)
				assert(not before_final or state.z<16.0,"Arc pre-final medical route crossed the final activation")
			if not arrived:
				push_error("Blocked Arc QA segment in %s toward %s at %s" % [capture.name,goal,state])
				quit(1)
				return
			count+=1
	print("test_arc_route: PASS %d ordinary shared-mirror waypoints and pre-final exclusion" % count)
	quit(0)
