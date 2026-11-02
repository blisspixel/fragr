extends SceneTree

const Launch = preload("res://scripts/m14_launch.gd")
var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated",true)
	_run.call_deferred()

func _check(value: bool,message: String) -> void:
	if not value:
		failures += 1
		push_error("test_m14_presentation: "+message)

static func fallen_boxes(origin: Vector3 = Vector3.ZERO) -> Array[AABB]:
	var boxes: Array[AABB] = [AABB(origin+Vector3(-3,0,-2),Vector3(6,1.6,4))]
	for x: float in [-3.6,1.8]:
		for z: float in [-2.6,1.4]:
			boxes.append(AABB(origin+Vector3(x,0,z),Vector3(1.8,0.55,1.2)))
	return boxes

func _run() -> void:
	var view: Node3D = Launch.new()
	root.add_child(view)
	view.configure_map({})
	_check(view.wreck == null and view.get_child_count() == 0,"unregistered maps never display a wreck")
	# Controlled geometry fixtures independently exercise every surface inside
	# the native-proposed fallen volumes, including translated disable locations.
	for origin: Vector3 in [Vector3.ZERO,Vector3(7,0,36),Vector3(9,0,31)]:
		var boxes: Array[AABB] = fallen_boxes(origin)
		view.wreck = Node3D.new()
		view.add_child(view.wreck)
		view._build_fallen_hull(boxes[0])
		for index: int in range(1,5):
			view._build_folded_leg(boxes[index],index)
		var mesh_refs: Array[WeakRef] = []
		for mesh: MeshInstance3D in view.wreck.get_children():
			mesh_refs.append(weakref(mesh))
			var actual: AABB = mesh.transform*mesh.get_aabb()
			var enclosed: bool = false
			for box: AABB in boxes:
				enclosed = enclosed or box.grow(0.001).encloses(actual)
			_check(enclosed,"fallen "+str(mesh.name)+" fits a registered body at "+str(origin))
		_check(view.wreck.get_node("GroundedFoot1").position.y < 0.1,"collapsed feet remain on the ground")
		view.clear_map()
		_check(view.wreck == null and view.get_child_count() == 0,"world rotation detaches all wreck pieces")
		await process_frame
		for reference: WeakRef in mesh_refs:
			_check(reference.get_ref() == null,"retired wreck nodes are released after the frame")
	var pad: Dictionary = {"solids":[{"min_x":22,"max_x":37,"min_z":38,"max_z":49,"top":0.2}]}
	view._build_launch_services(pad)
	_check(view._lamps.size() == 8,"retained pad hosts carry the fitted edge lights")
	view.apply_state({"id":"launch_authority","m14":{"machine_fallen":true}})
	_check(view.state_applied == 0 and view._pad_material.albedo_color == Launch.HELD,"unvalidated mission state cannot release a pad")
	view.clear_map()
	pad["solids"][0]["max_x"] = 38
	view._build_launch_services(pad)
	_check(view._lamps.is_empty(),"changed unreviewed hosts omit fitted hardware")
	view.clear_map()
	_check(view._lamps.is_empty() and view._pad_material == null,"map retirement releases lamp references and state material")
	var golden: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://golden/m14_fact_vectors.json"))
	var cover := ArenaCover.new()
	root.add_child(cover)
	for map_key: String in ["map_info","fallen_map_info"]:
		cover.apply_map_info(golden[map_key])
		var terminal_index: int = int(golden[map_key]["m14"]["departure"]["decoration"])
		var terminal: WorldSign = cover.get_node("Detail_%d_terminal/Copy" % terminal_index)
		_check(terminal.message_key == "WORLD_M14_DEPARTURE_CONSOLE" and terminal.text.contains("DEPARTURE"),"registered launch console never advertises a pending transfer review")
	cover.free()
	for sample: Dictionary in golden["valid"]:
		var fallen: bool = sample["state"]["m14"]["machine_fallen"]
		var info: Dictionary = golden["fallen_map_info"] if fallen else golden["map_info"]
		view.configure_map(info)
		_check(not view._geometry.is_empty(),"native "+sample["name"]+" registers presentation")
		_check((view.wreck != null) == fallen,"native fallen map alone determines the wreck")
		view.apply_state(sample["state"])
		_check(view.state_applied == 1,"native "+sample["name"]+" facts accepted")
		_check(view._pad_material != null,"native launch hosts create pad material")
		_check(view._lamps.size() == 14,"native launch hosts carry eight pad and six gantry lights")
		if view._pad_material != null:
			_check(view._pad_material.albedo_color == (Launch.RELEASED if fallen else Launch.HELD),"native fallen receipt alone releases the lights")
		if fallen:
			var boxes: Array[AABB] = []
			for index: Variant in info["m14"]["walker_solids"]:
				boxes.append(Launch._solid_bounds(info["solids"][int(index)]))
			for mesh: MeshInstance3D in view.wreck.get_children():
				var actual: AABB = mesh.transform*mesh.get_aabb()
				var enclosed: bool = false
				for box: AABB in boxes:
					enclosed = enclosed or box.grow(0.001).encloses(actual)
				_check(enclosed,"native translated wreck encloses "+str(mesh.name))
		var previous_count: int = view.state_applied
		var mismatch: Dictionary = sample["state"].duplicate(true)
		mismatch["m14"]["machine_fallen"] = not fallen
		view.apply_state(mismatch)
		_check(view.state_applied == previous_count,"facts from the other geometry cannot change launch presentation")
		view.clear_map()
		await process_frame
	for sample: Dictionary in golden["invalid"]:
		var fallen: bool = sample["state"].get("m14",{}).get("machine_fallen",false)
		view.configure_map(golden["fallen_map_info"] if fallen else golden["map_info"])
		view.apply_state(sample["state"])
		_check(view.state_applied == 0,"native malformed "+sample["name"]+" cannot change launch presentation")
	view.clear_map()
	view.configure_map(golden["map_info"])
	var reports: Array[String] = []
	view.notice_requested.connect(func(line: String) -> void: reports.append(line))
	var approach: Dictionary = golden["valid"][1]["state"].duplicate(true)
	var before: Dictionary = approach.duplicate(true)
	before["m14"]["completed"] = before["m14"]["completed"].slice(0,3)
	before["m14"]["current"] = golden["map_info"]["m14"]["objectives"][3].duplicate(true)
	view.apply_state(before)
	_check(reports.is_empty(),"road clearance alone does not announce the overlook")
	view.apply_state(approach)
	_check(reports.size()==1 and reports[0]==tr(Launch.REPORT_KEY),"accepted approach clearance emits localized Mara report once")
	_check(view._flares.size()==2 and not view._flares[1].visible,"other-site flares are sequential")
	view._advance_flares(2.0)
	_check(view._flares[0].visible and view._flares[1].visible,"second flare rises after its bounded delay")
	for flare: Node3D in view._flares:
		for mesh: MeshInstance3D in flare.get_children():
			var bounds: AABB = mesh.global_transform*mesh.get_aabb()
			_check(bounds.position.z>float(golden["map_info"]["half_extent"]),"entire flare remains outside playable collision")
	view.apply_state(before)
	view.apply_state(approach)
	_check(reports.size()==1,"stale regression and repeated facts cannot replay report")
	view.configure_map(golden["map_info"])
	view.apply_state(before)
	view.apply_state(approach)
	_check(reports.size()==1 and view._flares.is_empty(),"same-contract MapInfo refresh preserves report and stale-state guard")
	var retry: Dictionary = golden["valid"][-1]["state"].duplicate(true)
	view.apply_state(retry)
	var next_approach: Dictionary = approach.duplicate(true)
	next_approach["attempt"] = retry["attempt"]
	next_approach["changed_at"] = retry["changed_at"]
	view.apply_state(next_approach)
	_check(reports.size()==2,"fresh retry can introduce its own overlook report")
	view._advance_flares(20.0)
	_check(view._flares.is_empty() and view._flare_elapsed<0.0,"finished effects retire instead of blinking forever")
	view.clear_map()
	view.configure_map(golden["map_info"])
	view.apply_state(approach)
	_check(reports.size()==2 and view._flares.is_empty(),"late hydration does not replay an old report")
	view.clear_map()
	_check(view._previous_message.is_empty() and view._report_attempt.is_empty(),"map retirement clears retained attempt identity")
	view.queue_free()
	await process_frame
	if failures == 0:
		print("test_m14_presentation: PASS")
	quit(0 if failures == 0 else 1)
