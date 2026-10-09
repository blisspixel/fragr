extends SceneTree

## The retained failed guard is on the real west stair, behind the cabin search.
class SearchCamera extends Node3D:
	var fp_yaw: float = 0.0
	var fp_pitch: float = 0.0

var _failures: Array[String] = []
var _solids: Array = []
var _world: Dictionary = {}
var _guard: Dictionary = {"x":-6.499695,"y":4.1,"z":-10.025003,"campaign":{"kind":"clerk"}}
var _manager: Node
var _camera: SearchCamera
var _driver: QaCombat

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _run() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../server/maps/m10_common_carrier.json"))
	var tour: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://qa/m10_common_carrier.json"))
	for row: Dictionary in source.solids:
		_solids.append({"min_x":row.min[0],"max_x":row.max[0],"min_z":row.min[2],"max_z":row.max[2],"bottom":row.min[1],"top":row.max[1]})
	_world = {"half":source.half_extent,"solids":_solids}
	var spec: Dictionary = {}
	for state: Dictionary in tour.states:
		if state.name == "m10_passenger_defense":
			spec = state.combat
	_check(spec.required == ["passenger_clerk_a","passenger_clerk_b","passenger_sweeper","passenger_enforcer"], "all four actual guards remain required")
	_check(QaCombat.valid_finish_search_route(spec), "final defense uses a strict bounded finish flag")
	for bad: Dictionary in [{"finish_search_route":1},{"finish_search_route":"true"},{"finish_search_route":true},{"finish_search_route":true,"search_route":[]},{"finish_search_route":true,"search_route":[[0,0,INF]]}]:
		_check(not QaCombat.valid_finish_search_route(bad), "malformed or absent return route fails closed")
	_check(QaCombat.valid_finish_search_route({}) and QaCombat.valid_finish_search_route({"finish_search_route":false}), "default and explicit opt-out remain valid")
	var route: Array = spec.search_route
	var old: Dictionary = _walk(Vector3(3.2115338,4.8,-11.784864),route.slice(0,4))
	_check(old.reached and not old.visible, "retained failed cabin-only route cannot see the actual recorded clerk")
	var full: Dictionary = _walk(Vector3(3.2115338,4.8,-11.784864),route)
	_check(full.reached and full.visible and full.ticks < 500, "ordinary stair loop exposes the guard and returns within the unchanged 25 seconds before combat")
	_manager = Node.new()
	root.add_child(_manager)
	_camera = SearchCamera.new()
	_camera.name = "SpectatorCamera"
	_manager.add_child(_camera)
	_driver = QaCombat.new()
	var me: Dictionary = {"x":3.2115338,"y":6.3,"z":-11.784864}
	for default_spec: Dictionary in [{},{"finish_search_route":false},spec]:
		QaCombat.release_inputs()
		var index: int = 0 if default_spec == spec else 1
		_check(_driver.finish_search_step(_manager,me,default_spec,route,index) == index and not Input.is_action_pressed("move_forward"), "disabled or unstarted search never adds movement")
	var returns: int = 0
	for prefix: Dictionary in full.prefixes:
		if prefix.index <= 0 or prefix.index >= route.size():
			continue
		var result: Dictionary = _finish(prefix.position,route,prefix.index,spec)
		_check(result.reached and not result.fired and result.ticks < 500, "actual completion inputs finish the remaining loop without firing from prefix %d" % prefix.index)
		returns += 1
	_check(returns == route.size()-1, "every interrupted search prefix has a measured return")
	_check_mobile_heavy(tour)
	QaCombat.release_inputs()
	_manager.free()
	await process_frame
	if not _failures.is_empty():
		for failure: String in _failures:
			push_error("test_m10_search_route: " + failure)
		quit(1)
		return
	print("test_m10_search_route: PASS (recorded occlusion negatives, west16/east19-point loops, 15/18 interrupted returns, no-fire/default controls)")
	quit(0)

func _check_mobile_heavy(tour: Dictionary) -> void:
	var spec: Dictionary = {}
	for state: Dictionary in tour.states:
		if state.name == "m10_aft_heavy":
			spec = state.combat
	_check(spec.get("required") == ["aft_heavy"] and spec.get("engagement_distance") == 12
		and spec.get("finish_search_route") == true, "mobile Heavy keeps the actual required death and original Scatter range")
	var previous: Dictionary = _guard
	# Retained actual failed snapshot, including its server presentation offset.
	_guard = {"x":6.4999986,"y":9.1,"z":12.067554,"campaign":{"kind":"heavy_sweeper"}}
	var route: Array = spec.search_route
	var start: Vector3 = Vector3(0,2,10)
	var old: Dictionary = _walk(start,route.slice(0,3))
	_check(old.reached and not old.visible, "retained lower-only search cannot see the actual supported upper Heavy")
	var full: Dictionary = _walk(start,route)
	_check(route.size() == 19 and full.reached and full.visible and full.ticks < 500,
		"ordinary east-stair search exposes the mobile Heavy and returns within the unchanged deadline")
	var returns: int = 0
	for prefix: Dictionary in full.prefixes:
		if prefix.index <= 0 or prefix.index >= route.size():
			continue
		var result: Dictionary = _finish(prefix.position,route,prefix.index,spec)
		_check(result.reached and not result.fired and result.ticks < 500,
			"Heavy's actual completion inputs return without firing from prefix %d" % prefix.index)
		returns += 1
	_check(returns == 18, "all interrupted Heavy search prefixes retain an ordinary measured return")
	_guard = previous

func _walk(start: Vector3, route: Array) -> Dictionary:
	var state: Dictionary = MoveStep.make_state(start.x,start.z,0.0)
	state.y = start.y
	var ticks: int = 0
	var visible: bool = false
	var prefixes: Array = []
	for index: int in route.size():
		var goal: Array = route[index]
		var arrived: bool = false
		for tick: int in 300:
			visible = visible or QaCombat.exposed_point(_guard,Vector3(state.x,state.y+1.6,state.z),_solids).is_finite()
			if Vector2(state.x-goal[0],state.z-goal[2]).length()<0.28 and absf(state.y-goal[1])<0.03:
				arrived = true
				break
			var yaw: float = atan2(goal[2]-state.z,goal[0]-state.x)
			state = MoveStep.live_step(state,MoveStep.make_input(true,false,false,false,yaw),MoveStep.TOP_SPEED,MoveStep.DT_LIVE,_world)
			ticks += 1
		if not arrived:
			return {"reached":false,"visible":visible,"ticks":ticks,"prefixes":prefixes}
		prefixes.append({"index":index+1,"position":Vector3(state.x,state.y,state.z)})
	return {"reached":true,"visible":visible,"ticks":ticks,"prefixes":prefixes}

func _finish(start: Vector3, route: Array, index: int, spec: Dictionary) -> Dictionary:
	var state: Dictionary = MoveStep.make_state(start.x,start.z,0.0)
	state.y = start.y
	var ticks: int = 0
	var fired: bool = false
	while index < route.size() and ticks < 500:
		QaCombat.release_inputs()
		index = _driver.finish_search_step(_manager,{"x":state.x,"y":state.y+1.5,"z":state.z},spec,route,index)
		fired = fired or Input.is_action_pressed("fire")
		state = MoveStep.live_step(state,MoveStep.make_input(Input.is_action_pressed("move_forward"),Input.is_action_pressed("move_back"),Input.is_action_pressed("move_left"),Input.is_action_pressed("move_right"),_camera.fp_yaw),MoveStep.TOP_SPEED,MoveStep.DT_LIVE,_world)
		ticks += 1
	return {"reached":index == route.size(),"fired":fired,"ticks":ticks}

func _check(passed: bool, message: String) -> void:
	if not passed:
		_failures.append(message)
