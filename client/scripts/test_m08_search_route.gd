extends SceneTree

class SearchCamera extends Node3D:
	var fp_yaw: float=0.0
	var fp_pitch: float=0.0

var _failures: Array[String]=[]
var _arena: Dictionary={}
var _peers: Array[Dictionary]=[]

func _initialize() -> void:
	set_meta("fragr_automated",true)
	call_deferred("_run")

func _run() -> void:
	var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../server/maps/m08_custodian_of_record.json"))
	var tour: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://qa/m08_custodian_of_record.json"))
	var solids: Array[Dictionary]=[]
	for item: Dictionary in source.solids:
		solids.append({"min_x":item.min[0],"max_x":item.max[0],"min_z":item.min[2],"max_z":item.max[2],"bottom":item.min[1],"top":item.max[1]})
	_arena={"half":source.half_extent,"solids":solids}
	var cleanup: Dictionary={}
	var bridge: Dictionary={}
	var bridge_weapon: String=""
	var counter: Dictionary={}
	var arrival: Array=[]
	var noise: Dictionary={}
	var counter_index: int=-1
	var noise_index: int=-1
	for capture: Dictionary in tour.states:
		match capture.name:
			"m08_mine_cleanup": cleanup=capture.combat
			"m08_bridge_fight":
				bridge=capture.combat
				bridge_weapon=capture.get("weapon","" )
			"m08_exit_counter":
				counter=capture.combat
				counter_index=tour.states.find(capture)
			"m08_authorized_noise":
				noise=capture
				noise_index=tour.states.find(capture)
			"m08_exit_arrival": arrival=capture.walk_to
	_check(cleanup.required==["post_sweeper_a","post_sweeper_b"] and cleanup.approach_route==[[-16.0,3.0,17.0],[-13.0,3.0,17.5],[-10.0,3.0,17.0],[-10.0,3.0,10.0]] and cleanup.search_route==[[10.0,3.0,9.0],[16.0,3.0,1.0],[16.0,3.0,-6.0]],"mine corridor retains its original physical points and both required guards while ordinary fire resumes outside")
	_check(bridge.required==["well_auditor","well_sweeper_west","well_sweeper_east","well_sweeper_north","bridge_clerk_near","bridge_clerk_far"],"all six bridge guards retain actual required deaths")
	_check(bridge_weapon=="Rail","bridge retains the intended ranged weapon selection")
	var bridge_points: Array=bridge.search_route
	_check(bridge_points.slice(0,4)==[[1.0,6.0,8.5],[-10.0,6.0,9.0],[12.0,6.0,8.0],[1.0,6.0,8.5]],"original bridge search prefix remains physical and unchanged")
	var bridge_walk: Dictionary=_walk(Vector3(1.211782,6,8.490375),bridge_points)
	_check(bridge_points.size()==7 and bridge_walk.reached and bridge_walk.ticks<500,"supported existing bridge vantages fit the original deadline")
	# Actual surviving positions from the retained ordinary bridge failure.
	var guards: Array[Dictionary]=[
		{"x":27.499998,"y":7.5,"z":1.9779463,"campaign":{"kind":"auditor"}},
		{"x":15.327799,"y":7.5,"z":2.5000005,"campaign":{"kind":"sweeper"}},
		{"x":17.59089,"y":7.5,"z":2.6351233,"campaign":{"kind":"sweeper"}}
	]
	for guard: Dictionary in guards:
		_check(not QaCombat.exposed_point(guard,Vector3(1.211782,7.6,8.490375),solids).is_finite(),"original final point retains the actual late-guard occlusion negative")
		var visible: bool=false
		for point: Array in bridge_points.slice(4):
			visible=visible or QaCombat.exposed_point(guard,Vector3(point[0],point[1]+1.6,point[2]),solids).is_finite()
		_check(visible,"actual added bridge vantage exposes a retained survivor")
	var neutral_info: Dictionary=_layout_info(source,solids)
	var neutral_layout: Dictionary=M08NeutralBodies.layout(neutral_info)
	_check(not neutral_layout.is_empty(),"canonical archive panels bind all released civilian contact")
	for person: Dictionary in M08NeutralBodies.people(neutral_layout,true,true):
		_peers.append(ActorContact.stationary(person.key,person.feet))
	# These are exact authored prepared-stage replacements, not extra obstacles.
	_replace_stage(source,source.m08.seal.solid,source.m08.seal.open)
	_replace_stage(source,source.m08.machine.solid,source.m08.machine.fallen)
	for node: Dictionary in source.m08.nodes:
		_replace_stage(source,node.solid,node.fallen)
	var failed_feet: Vector3=Vector3(-0.0025645979,0,28.066355)
	var blocked: Dictionary=_walk(failed_feet,[[0,0,27]])
	_check(not blocked.reached and blocked.feet.distance_to(failed_feet)<0.001,"released civilians retain the exact old mandatory lower goal obstruction")
	var kept: Array[Dictionary]=_peers
	_peers=[]
	_check(_walk(failed_feet,[[0,0,27]]).reached,"static geometry alone preserves the old-goal negative control")
	_check(not _walk(Vector3(0,0,27),arrival).reached,"old lower-lane to upper waypoint cannot shortcut through the real enclosing wall")
	_peers=kept
	_check(_walk(failed_feet,[[0,0,29.5]]).reached,"corrected lower arrival avoids the actual released contact row")
	var exit_region: Dictionary=source.m08.objectives.back().arrival
	_check(M03MissionState._inside([0,0,29.5],exit_region),"bounded goal remains inside unchanged exit objective")
	_check(counter.required==["exit_clerk_west","exit_clerk_east","exit_sweeper_west","exit_sweeper_east","exit_heavy"] and counter.get("finish_search_route")==true,"all five counterattack guards retain actual deaths and ordinary completion return")
	var route: Array=counter.search_route
	_check(noise_index==counter_index+1 and noise.strip_frames==16 and noise.strip_interval_seconds==0.25,"original timed noise observation follows required counterattack clearance")
	_check(route.slice(0,2)==[[13.5,6.0,8.0],[8.5,6.0,18.0]] and noise.walk_to==[[8.5,6.0,22.0]],"all original noise approach points remain physical search inputs and the same final view")
	_check(route.slice(2,7)==[[8.5,6.0,22.0],[8.5,0.0,34.5],[5.0,0.0,34.8],[4.5,0.0,31.0],[0.0,0.0,29.5]],"freight descent retains its supported prefix and bounded contact-aware lower arrival")
	var loop: Dictionary=_walk(Vector3(13.1070566,6,8.0003653),route)
	_check(route.size()==11 and loop.reached and loop.ticks<500,"bottom-mouth return and supported ascent fit unchanged500ticks")
	_check(_walk(loop.feet,arrival).reached,"unchanged next arrival begins after a real supported ascent")
	var manager: Node=Node.new()
	root.add_child(manager)
	var camera: SearchCamera=SearchCamera.new()
	camera.name="SpectatorCamera"
	manager.add_child(camera)
	var driver:=QaCombat.new()
	var returns: int=0
	for prefix: Dictionary in loop.prefixes:
		if prefix.index>=route.size():
			continue
		var result: Dictionary=_finish(prefix.feet,route,prefix.index,counter,driver,manager,camera)
		_check(result.reached and not result.fired and result.ticks<500,"actual counterattack completion returns without firing from prefix%d"%prefix.index)
		returns+=1
	_check(returns==10,"all ten interrupted freight search prefixes have a measured ordinary return")
	QaCombat.release_inputs()
	manager.free()
	await process_frame
	for failure: String in _failures:
		push_error("test_m08_search_route: "+failure)
	if _failures.is_empty():
		print("test_m08_search_route: PASS (required guards, retained bridge occlusion,7point bridge/11point freight loops,10 contact-aware no-fire returns,released-lane and wall negatives)")
	quit(0 if _failures.is_empty() else 1)

func _walk(start: Vector3,route: Array) -> Dictionary:
	var body: Dictionary=MoveStep.make_state(start.x,start.z,0)
	body.y=start.y
	var ticks: int=0
	var prefixes: Array[Dictionary]=[]
	for index: int in route.size():
		var point: Array=route[index]
		var arrived: bool=false
		for _tick: int in 300:
			if Vector2(body.x-point[0],body.z-point[2]).length()<0.28 and absf(body.y-point[1])<0.04:
				arrived=true
				break
			var yaw: float=atan2(point[2]-body.z,point[0]-body.x)
			body=_advance(body,MoveStep.make_input(true,false,false,false,yaw))
			ticks+=1
		if not arrived:
			return {"reached":false,"ticks":ticks,"feet":Vector3(body.x,body.y,body.z),"prefixes":prefixes}
		prefixes.append({"index":index+1,"feet":Vector3(body.x,body.y,body.z)})
	return {"reached":true,"ticks":ticks,"feet":Vector3(body.x,body.y,body.z),"prefixes":prefixes}

func _finish(start: Vector3,route: Array,index: int,spec: Dictionary,driver: QaCombat,manager: Node,camera: SearchCamera) -> Dictionary:
	var body: Dictionary=MoveStep.make_state(start.x,start.z,0)
	body.y=start.y
	var ticks: int=0
	var fired: bool=false
	while index<route.size() and ticks<500:
		QaCombat.release_inputs()
		index=driver.finish_search_step(manager,{"x":body.x,"y":body.y+1.5,"z":body.z},spec,route,index)
		fired=fired or Input.is_action_pressed("fire")
		body=_advance(body,MoveStep.make_input(Input.is_action_pressed("move_forward"),Input.is_action_pressed("move_back"),Input.is_action_pressed("move_left"),Input.is_action_pressed("move_right"),camera.fp_yaw))
		ticks+=1
	return {"reached":index==route.size(),"ticks":ticks,"fired":fired}

func _check(condition: bool,message: String) -> void:
	if not condition:
		_failures.append(message)

func _advance(body: Dictionary,input: Dictionary) -> Dictionary:
	var proposed: Dictionary=MoveStep.live_step(body,input,MoveStep.TOP_SPEED,MoveStep.DT_LIVE,_arena)
	if _peers.is_empty():
		return proposed
	var bodies: Array[Dictionary]=[{"key":"participant","from":body,"proposed":proposed,"height":MoveStep.BODY_HEIGHT,"radius":MoveStep.RADIUS,"jump":false}]
	bodies.append_array(_peers)
	return ActorContact.resolve(bodies,MoveStep.DT_LIVE,_arena)[0]

func _layout_info(source: Dictionary,solids: Array[Dictionary]) -> Dictionary:
	var ids: Dictionary={}
	var surfaces: Array=[]
	for index: int in source.solids.size():
		ids[source.solids[index].id]=index
		surfaces.append(source.solids[index].surface)
	var decorations: Array=[]
	for item: Dictionary in source.decorations:
		var detail: Dictionary=item.duplicate(true)
		detail.solid=ids[detail.solid]
		decorations.append(detail)
	var departure: Dictionary=source.m08.departure.panel.duplicate(true)
	departure.solid=ids[departure.solid]
	decorations.append(departure)
	return {"geometry_version":2,"map_id":source.map_id,"half_extent":source.half_extent,"solids":solids,"presentation":{"ground":source.ground,"solids":surfaces,"decorations":decorations}}

func _replace_stage(source: Dictionary,id: String,box: Dictionary) -> void:
	for index: int in source.solids.size():
		if source.solids[index].id==id:
			_arena.solids[index]={"min_x":box.min[0],"max_x":box.max[0],"bottom":box.min[1],"top":box.max[1],"min_z":box.min[2],"max_z":box.max[2]}
			return
	_check(false,"prepared stage names an existing canonical solid")