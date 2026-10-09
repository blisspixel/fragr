extends SceneTree

var _failures: Array[String] = []
var _world: Dictionary = {}
var _notary: Dictionary = {"x":19.0,"y":8.0,"z":13.919999,"campaign":{"side":"union","kind":"notary","phase":"moving","phase_started":2513,"phase_ends":2513}}

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _run() -> void:
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../server/maps/m09_passenger_manifest.json"))
	var tour: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://qa/m09_passenger_manifest.json"))
	var solids: Array[Dictionary] = []
	for row: Dictionary in map.solids:
		solids.append({"min_x":row.min[0],"max_x":row.max[0],"min_z":row.min[2],"max_z":row.max[2],"bottom":row.min[1],"top":row.max[1]})
	_world = {"half":map.half_extent,"solids":solids}
	var fight: Dictionary = {}
	var arrival: Dictionary = {}
	for state: Dictionary in tour.states:
		if state.name == "m09_gantry_three_clear":
			fight = state
		if state.name == "m09_clamps_release":
			arrival = state
	var spec: Dictionary = fight.get("combat", {})
	_check(fight.get("weapon") == "Rail" and spec.get("required") == ["gantry_three_enforcer","gantry_three_sweeper","cradle_notary_east"] and spec.get("engagement_distance") == 55,
		"all three actual guards, finite Rail selection and original range remain required")
	var route: Array = spec.get("search_route", [])
	_check(route.size() == 6, "the original four search points retain exactly two inner-vantage additions")
	var original: Dictionary = _walk(Vector3(30,10,24.5), route.slice(0,4))
	var candidate: Dictionary = _walk(Vector3(30,10,24.5), route)
	_check(original.reached and not original.visible, "original centre route remains occluded to the recorded lower Notary")
	_check(candidate.reached and candidate.visible and candidate.ticks < 500, "the supported inner vantage exposes that Notary inside the unchanged combat budget")
	var start: Vector3 = Vector3(29.07298,10,-17.62499)
	var empty: Dictionary = _walk(start, [[30,10,-18]])
	var blocked: Dictionary = _walk(start, [[30,10,-18]], true)
	var side: Dictionary = _walk(start, arrival.get("walk_to", []), true)
	_check(empty.reached and not blocked.reached, "a stationary crew member at the authored waiting point distinguishes contact from clear geometry")
	_check(side.reached and side.ticks < 300, "ordinary arrival walks around that crew body without relaxing contact")
	_check(arrival.get("expect_m09_hatch_open") == true and arrival.get("expect_m09_completed") == ["loading_cleared","lesson_cleared","crew_freed","gantry_one_cleared","gantry_two_cleared","gantry_three_cleared","clamps_released"],
		"the actual clamp and hatch facts remain required after the side approach")
	if not _failures.is_empty():
		for failure: String in _failures:
			push_error("test_m09_search_route: " + failure)
		quit(1)
		return
	print("test_m09_search_route: PASS (recorded Notary occlusion, supported inner vantage, stationary-crew refusal and ordinary side arrival)")
	quit(0)

func _walk(start: Vector3, points: Array, with_crew: bool = false) -> Dictionary:
	var body: Dictionary = MoveStep.make_state(start.x,start.z,0.0)
	body.y = start.y
	var ticks: int = 0
	var visible: bool = false
	for point: Array in points:
		var arrived: bool = false
		for _step: int in 300:
			visible = visible or QaCombat.exposed_point(_notary,Vector3(body.x,body.y+1.6,body.z),_world.solids).is_finite()
			if Vector2(body.x-point[0],body.z-point[2]).length() < 0.28 and absf(body.y-point[1]) < 0.03:
				arrived = true
				break
			var yaw: float = atan2(point[2]-body.z,point[0]-body.x)
			var proposed: Dictionary = MoveStep.live_step(body,MoveStep.make_input(true,false,false,false,yaw),MoveStep.TOP_SPEED,MoveStep.DT_LIVE,_world)
			if with_crew:
				var actor: Dictionary = ActorContact.stationary("participant",Vector3(body.x,body.y,body.z))
				actor.proposed = proposed
				var contacts: Array[Dictionary] = [actor,ActorContact.stationary("m09/tern",Vector3(30,10,-18))]
				body = ActorContact.resolve(contacts,MoveStep.DT_LIVE,_world)[0]
			else:
				body = proposed
			ticks += 1
		if not arrived:
			return {"reached":false,"visible":visible,"ticks":ticks}
	return {"reached":not points.is_empty(),"visible":visible,"ticks":ticks}

func _check(passed: bool, message: String) -> void:
	if not passed:
		_failures.append(message)
