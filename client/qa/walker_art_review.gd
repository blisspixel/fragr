extends SceneTree

## Controlled geometry/light fixtures, not server encounter or player evidence.
var _viewport: SubViewport
var _camera: Camera3D
var _walker: WalkerView
var _bounds: Array[AABB] = [AABB(Vector3(-3,3,-2),Vector3(6,3,4))]
var _triangles: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or DirAccess.make_dir_recursive_absolute(args[0]) != OK:
		push_error("walker_art_review: require an output directory")
		quit(1)
		return
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(960,720)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("282728")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("c4b2a1")
	_viewport.add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38,-35,0)
	key.light_energy = 1.2
	key.shadow_enabled = true
	_viewport.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-22,145,0)
	fill.light_energy = 0.48
	_viewport.add_child(fill)
	_viewport.add_child(AssessorRig.part("MarsGround",Vector3(50,0.1,50),Vector3(0,-0.05,0),Color("805342")))
	for x: float in [-5,5]:
		_viewport.add_child(AssessorRig.part("PersonScale",Vector3(0.2,1.8,0.2),Vector3(x,0.9,0),Color("c1b899")))
	_walker = WalkerView.new()
	_viewport.add_child(_walker)
	_walker.set_process(false)
	var golden: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://golden/walker_vectors.json"))
	_walker.configure_map(golden["map"])
	if _walker.machine == null:
		push_error("walker_art_review: native map failed to construct presenter")
		_viewport.free()
		quit(1)
		return
	for z: float in [-1.4,1.4]:
		for x: float in [-2.4,2.4]:
			_bounds.append(AABB(Vector3(x-0.6,0,z-0.6),Vector3(1.2,3,1.2)))
	_walker.stomp_ring.visible = false
	_camera = Camera3D.new()
	_camera.fov = 58
	_viewport.add_child(_camera)
	for child: Node in _walker.machine.get_children():
		if child is MeshInstance3D:
			_triangles += child.mesh.get_faces().size()/3
	var rows: Array[Dictionary] = []
	for lighting: String in ["neutral","dim"]:
		world.environment.ambient_light_energy = 0.55 if lighting == "neutral" else 0.16
		key.light_energy = 1.2 if lighting == "neutral" else 0.4
		fill.light_energy = 0.48 if lighting == "neutral" else 0.10
		for pose: Dictionary in [
			{"name":"front","eye":Vector3(9,1.8,-12),"phase":"dormant"},
			{"name":"twenty_metres","eye":Vector3(0,1.8,-20),"phase":"dormant"},
			{"name":"rear","eye":Vector3(-9,1.8,12),"phase":"dormant"},
			{"name":"roof","eye":Vector3(9,10,-11),"phase":"artillery_warning"},
			{"name":"recovery","eye":Vector3(8,1.8,-9),"phase":"recovery"},
			{"name":"disabled","eye":Vector3(9,1.8,-12),"phase":"disabled"},
		]:
			_camera.position = pose.eye
			_camera.look_at(Vector3(0,2.6,0))
			_walker.phase = pose.phase
			_walker._update_status(0 if pose.phase == "disabled" else 900,3 if pose.phase == "disabled" else 1)
			_walker._present()
			if not _check_bounds():
				_viewport.free()
				quit(1)
				return
			await process_frame
			await RenderingServer.frame_post_draw
			var name_at: String = lighting+"_"+str(pose.name)+".png"
			assert(_viewport.get_texture().get_image().save_png(args[0].path_join(name_at)) == OK)
			rows.append({"file":name_at,"phase":pose.phase})
	var report := FileAccess.open(args[0].path_join("review.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"controlled_fixture":true,"ordinary_input_acceptance":false,
		"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),
		"source_sha256":FileAccess.get_sha256("res://scripts/walker_view.gd"),"triangles":_triangles,
		"all_parts_inside_registered_boxes":true,"states":rows},"\t")+"\n")
	report.close()
	_viewport.free()
	await process_frame
	print("walker_art_review: PASS twelve geometry/light fixtures, no gameplay claim")
	quit(0)

func _check_bounds() -> bool:
	for child: Node in _walker.machine.get_children():
		if not child is MeshInstance3D:
			continue
		var visible_bounds: AABB = child.transform*child.get_aabb()
		var enclosed: bool = false
		for bounds: AABB in _bounds:
			enclosed = enclosed or bounds.grow(0.001).encloses(visible_bounds)
		if not enclosed:
			push_error("walker_art_review: part exceeds registered body: "+str(child.name)+" "+str(visible_bounds))
			return false
	return true
