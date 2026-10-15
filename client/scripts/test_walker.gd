extends SceneTree

var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated",true)
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_walker: "+message)

static func fixture_map() -> Dictionary:
	var solids: Array = [{"min_x":-3,"max_x":3,"min_z":-2,"max_z":2,"bottom":3,"top":6}]
	for x: float in [-3.0,1.8]:
		for z: float in [-2.0,0.8]:
			solids.append({"min_x":x,"max_x":x+1.2,"min_z":z,"max_z":z+1.2,"bottom":0,"top":3})
	return {"type":"map_info","map_id":1048,"map_name":"Continuance Walker (development)","geometry_version":2,"half_extent":40,"solids":solids,
		"walker":{"solids":[0,1,2,3,4],"stations":[[0,0,0],[8,0,0],[8,0,10]],"activation":{"min":[-30,0,-14],"max":[30,4,28]},"arena":{"min":[-32,0,-28],"max":[32,20,28]},"approach":[-12,0,-8]}}

static func fixture(phase: String = "dormant", tick: int = 0) -> Dictionary:
	return {"type":"snapshot","map_id":1048,"tick":tick,"players":[],"walker":{"hp":0 if phase=="disabled" else 900,"stage":3 if phase=="disabled" else 1,"phase":phase,"phase_started":0 if phase=="dormant" else tick,"phase_ends":0 if phase=="dormant" else tick+WalkerFacts.DURATIONS[phase],"feet":[0,0,0],"target":[-12,0,-8],"artillery_targets":[[-8,0,-8],[-12,0,-8],[-16,0,-8]],"shells_left":36,"shells":[]}}

func _run() -> void:
	var golden: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://golden/walker_vectors.json"))
	_check(MapGeometry.validation_error(golden["map"]).is_empty(),"actual native geometry crosses the client boundary")
	var cover := ArenaCover.new()
	root.add_child(cover)
	cover.apply_map_info(golden["map"])
	for index: Variant in golden["map"]["walker"]["solids"]:
		_check(not cover._solid_views[int(index)].visible,"wire numeric indices hide the original static body")
	_check(cover._solid_views[5].visible,"ordinary cover remains visible beside machinery")
	cover.queue_free()
	for sample: Dictionary in golden["valid"]:
		var wire: Dictionary = sample.duplicate(true)
		wire.erase("name")
		_check(WalkerFacts.validation_error(wire,golden["map"]).is_empty(),"native valid "+str(sample["name"]))
	for sample: Dictionary in golden["invalid"]:
		var wire: Dictionary = sample.duplicate(true)
		wire.erase("name")
		_check(not WalkerFacts.validation_error(wire,golden["map"]).is_empty(),"native invalid "+str(sample["name"]))
	_check_native_blasts(golden)
	var info: Dictionary = fixture_map()
	_check(MapGeometry.validation_error(info).is_empty(),"registered body and authored arena accepted")
	var static_panel: Dictionary = info.duplicate(true)
	static_panel["presentation"] = {"decorations":[{"solid":0}]}
	_check(not WalkerFacts.map_error(static_panel).is_empty(),"static decoration cannot remain on moving machinery")
	var wrong_map: Dictionary = fixture()
	wrong_map["map_id"] = 1047
	_check(not WalkerFacts.validation_error(wrong_map,info).is_empty(),"stale other-map machinery cannot bind to accepted map")
	_check(not WalkerFacts.validation_error({"walker":null}).is_empty(),"explicit null is not absent machinery")
	_check(not WalkerFacts.map_error({"walker":null}).is_empty(),"explicit null map machinery is invalid")
	for phase: String in WalkerFacts.PHASES:
		_check(WalkerFacts.validation_error(fixture(phase,12),info).is_empty(),"accept phase "+phase)
	for bad: Dictionary in [{"solids":[0,1,2,3,3]},{"solids":[0,1,2,3,99]},{"stations":[[0,0,0],[0,0,0],[8,0,10]]},{"stations":[[0,0,0],[8,1,0],[8,0,10]]},{"stations":[[0,0,0],[31,0,0],[8,0,10]]},{"approach":[100,0,0]},{"arena":{"min":[-32,0,-28],"max":[32,2,28]}},{"unknown":1}]:
		var broken: Dictionary = info.duplicate(true)
		broken["walker"].merge(bad,true)
		_check(not MapGeometry.validation_error(broken).is_empty(),"reject malformed body layout "+str(bad))
	for bad: Dictionary in [{"hp":-1},{"hp":901},{"hp":600},{"stage":2},{"phase":"invented"},{"phase_ends":31},{"feet":[0,1,0]},{"feet":[31,0,0]},{"feet":[NAN,0,0]},{"target":[0,-1,0]},{"artillery_targets":[]},{"shells_left":37},{"shells_left":35},{"phase_started":1},{"extra":true}]:
		var broken: Dictionary = fixture()
		broken["walker"].merge(bad,true)
		_check(not WalkerFacts.validation_error(broken,info).is_empty(),"reject forged snapshot "+str(bad))
	var live: Dictionary = fixture("artillery",100)
	live["walker"]["shells_left"] = 35
	live["walker"]["shells"] = [{"id":1,"position":[1,8,1],"velocity":[0,6,12],"age_ticks":2}]
	_check(WalkerFacts.validation_error(live,info).is_empty(),"actual finite shell accepted")
	for bad: Dictionary in [{"id":0},{"age_ticks":100},{"age_ticks":-1},{"velocity":[0,129,0]},{"position":[0,-1,0]},{"velocity":[0,INF,0]},{"extra":0}]:
		var broken: Dictionary = live.duplicate(true)
		broken["walker"]["shells"][0].merge(bad,true)
		_check(not WalkerFacts.validation_error(broken,info).is_empty(),"reject malformed shell "+str(bad))
	var duplicate: Dictionary = live.duplicate(true)
	duplicate["walker"]["shells"].append(duplicate["walker"]["shells"][0].duplicate(true))
	_check(not WalkerFacts.validation_error(duplicate,info).is_empty(),"shell identities are unique and stock is finite")
	_check(not WalkerFacts.validation_error({"tick":12},info).is_empty(),"registered machine cannot disappear from snapshot")
	_check(WalkerFacts.validation_error({"tick":12}).is_empty(),"ordinary historical maps need no machine facts")
	var disabled: Dictionary = live.duplicate(true)
	disabled["walker"].merge({"hp":0,"stage":3,"phase":"disabled","phase_started":100,"phase_ends":100},true)
	_check(WalkerFacts.validation_error(disabled,info).is_empty(),"committed shell survives machine disable")
	var expired: Dictionary = fixture("recovery",12)
	expired["tick"] = 72
	_check(not WalkerFacts.validation_error(expired,info).is_empty(),"completed recovery cannot claim a live phase")
	var translated: Dictionary = WalkerFacts.translated_solid(info,0,[8,0,10])
	_check(translated["min_x"]==5 and translated["min_z"]==8 and translated["bottom"]==3,"current world translates exact registered body")
	var prediction := LocalPrediction.new()
	prediction.configure_map(info)
	var moving: Dictionary = fixture("relocating",80)
	moving["walker"]["feet"] = [4,0,0]
	prediction.apply_walker(moving)
	_check(prediction.arena["solids"][0]["min_x"]==1 and prediction._walker_moving,"moving collision follows snapshot and suspends speculative movement")
	var settled: Dictionary = fixture("recovery",90)
	settled["walker"]["feet"]=[4,0,0]
	prediction.apply_walker(settled)
	_check(not prediction._walker_moving and prediction.arena["solids"][0]["min_x"]==1,"recovery restores prediction against accepted collision")
	prediction.apply_walker(moving)
	_check(not prediction._walker_moving and prediction._walker_tick==90,"stale machine samples cannot undo accepted collision phase")
	var driving := VehiclePrediction.new()
	driving.configure_map(info)
	driving.accept_vehicles(moving,"")
	_check(driving._walker_moving and driving.arena["solids"][0]["min_x"]==1,"vehicle world shares authoritative translated machine and motion guard")
	driving.accept_vehicles(settled,"")
	_check(not driving._walker_moving,"vehicle guard releases at accepted recovery")
	var ordinary: Dictionary = info.duplicate(true)
	ordinary.erase("walker")
	prediction.configure_map(ordinary)
	_check(not prediction._walker_moving and prediction._walker_geometry.is_empty(),"map change releases machine prediction guard")
	var network: Node = preload("res://scripts/net_client.gd").new()
	var errors: Array[String] = []
	network.server_error.connect(func(reason: String) -> void: errors.append(reason))
	network._handle_message(JSON.stringify(info))
	_check(errors.is_empty() and not network.walker_geometry.is_empty(),"native wire map establishes machine identity")
	network._handle_message(JSON.stringify(fixture()))
	_check(errors.is_empty(),"registered snapshot crosses actual network boundary")
	network._handle_message(JSON.stringify({"type":"snapshot","tick":1,"players":[]}))
	_check(errors.size()==1 and network.walker_geometry.is_empty(),"missing registered state closes and clears the connection")
	network.free()
	var view := WalkerView.new()
	root.add_child(view)
	view.configure_map(info)
	view.apply(fixture())
	_check(view.machine!=null and not view.stomp_ring.visible and view.cue_count==0,"initial sync is silent")
	_check(view.status_label.visible and view.status_label.text.contains("900/900") and view.status_label.text.contains("1/3"),"accepted integrity and stage are visible to every viewer")
	_check_art_bounds(view,info)
	view.apply(fixture("stomp_warning",10))
	_check(view.stomp_ring.visible and view.cue_count==1,"accepted tell presents one warning")
	view.apply(fixture("stomp_warning",10))
	_check(view.cue_count==1,"repeated snapshot cannot replay warning")
	view.apply(fixture("recovery",50))
	_check(not view.stomp_ring.visible and view.vents[0].visible,"recovery opens actual joint vents and clears danger ring")
	_check_art_bounds(view,info)
	var damaged: Dictionary = fixture("recovery",51)
	damaged["walker"].merge({"hp":299,"stage":3},true)
	view.apply(damaged)
	_check(view.status_label.text.contains("299/900") and view.status_label.text.contains("3/3"),"actual damage and stage replace the progress cue")
	view.apply(live)
	_check(view.shells.size()==1 and view.markers[0].visible,"finite projectile and locked artillery marks appear")
	view.apply(disabled) # Same tick must not replace the accepted sample.
	_check(view.phase=="artillery","out-of-order presentation is ignored")
	disabled["tick"]=101
	view.apply(disabled)
	_check(view.phase=="disabled" and view.shells.size()==1 and view.markers[0].visible,"disable keeps committed shell warning until impact")
	_check(view.status_label.text.contains("DISABLED") and not view.status_label.text.contains("900/900"),"accepted disable retires the live integrity reading")
	# Exercise the actual compact native encoding, including omitted zero bottom.
	view.configure_map(golden["map"])
	_check(view.machine!=null,"native omitted default heights build a live machine")
	_check_art_bounds(view,golden["map"])
	view.configure_map(ordinary)
	_check(view.machine==null and view.status_label==null and view.shells.is_empty() and view.geometry.is_empty(),"map rotation retires machine resources")
	view.queue_free()
	await process_frame
	await process_frame
	if failures==0:
		print("test_walker: PASS")
	quit(0 if failures==0 else 1)

func _check_native_blasts(golden: Dictionary) -> void:
	var native_vehicle: Dictionary = golden.get("vehicle_blast",{})
	_check(not native_vehicle.is_empty() and not native_vehicle.get("explosions",[]).is_empty(),"actual burning vehicle publishes its resolved blast")
	_check(GrenadeFacts.validation_error(native_vehicle).is_empty(),"actual native vehicle destruction crosses the shared effects boundary")
	var blasts: Array = golden.get("blasts",[])
	_check(blasts.size()==2,"both real machine blast kinds have native boundary evidence")
	for sample: Dictionary in blasts:
		var snapshot: Dictionary = sample["snapshot"]
		var label: String = str(sample["name"])
		_check(GrenadeFacts.validation_error(snapshot).is_empty(),"native "+label+" blast crosses the shared effects boundary")
		var results: Array = snapshot.get("explosions",[])
		_check(not results.is_empty() and not results[0]["hits"].is_empty(),"native "+label+" records actual participant damage")
		if results.is_empty() or results[0]["hits"].is_empty():
			continue
		var bad: Dictionary = snapshot.duplicate(true)
		bad["explosions"][0]["radius"] = 7.25
		_check(not GrenadeFacts.validation_error(bad).is_empty(),label+" cannot invent a new radius")
		bad = snapshot.duplicate(true)
		bad["explosions"][0]["hits"][0]["hp_damage"] = 56 if label == "stomp" else 61
		bad["explosions"][0]["hits"][0]["armor_damage"] = 0
		_check(not GrenadeFacts.validation_error(bad).is_empty(),label+" cannot exceed its native peak")
		bad = snapshot.duplicate(true)
		bad["explosions"][0]["owner_id"] = "00000000-0000-4000-8000-000000000123"
		bad["explosions"][0]["hits"][0]["hp_damage"] = 55 if label == "stomp" else 60
		bad["explosions"][0]["hits"][0]["armor_damage"] = 0
		_check(not GrenadeFacts.validation_error(bad).is_empty(),label+" cannot lend machine damage to a participant's device")
		var vehicle: Dictionary = snapshot.duplicate(true)
		vehicle["explosions"][0]["radius"] = 5.0
		vehicle["explosions"][0]["hits"][0]["hp_damage"] = 80
		vehicle["explosions"][0]["hits"][0]["armor_damage"] = 0
		_check(GrenadeFacts.validation_error(vehicle).is_empty(),"an unowned vehicle blast keeps its own damage contract beside a Walker")

func _check_art_bounds(view: WalkerView, info: Dictionary) -> void:
	if view.machine == null:
		return
	var origin: Vector3 = GrenadeFacts.vector(info["walker"]["stations"][0])
	var bounds: Array[AABB] = []
	for index: int in info["walker"]["solids"]:
		var solid: Dictionary = info["solids"][index]
		var low := Vector3(float(solid["min_x"]),float(solid.get("bottom",0.0)),float(solid["min_z"]))
		var high := Vector3(float(solid["max_x"]),float(solid.get("top",MoveStep.WALL_TOP)),float(solid["max_z"]))
		bounds.append(AABB(low-origin,high-low).grow(0.001))
	for child: Node in view.machine.get_children():
		if not child is MeshInstance3D:
			continue
		var visible_bounds: AABB = child.transform*child.get_aabb()
		var enclosed: bool = false
		for region: AABB in bounds:
			enclosed = enclosed or region.encloses(visible_bounds)
		_check(enclosed,"rendered "+str(child.name)+" fits a registered body box")
