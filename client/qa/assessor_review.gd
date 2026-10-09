extends SceneTree

## Controlled mechanical presentation fixtures. These do not establish combat outcomes.
var _viewport: SubViewport
var _camera: Camera3D
var _rig: AssessorRig
var _world: WorldEnvironment
var _rows: Array[Dictionary] = []

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1 or DirAccess.make_dir_recursive_absolute(args[0]) != OK:
		push_error("assessor_review: require a receipt directory")
		quit(1)
		return
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1024, 768)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	_world = WorldEnvironment.new()
	_world.environment = Environment.new()
	_world.environment.background_mode = Environment.BG_COLOR
	_world.environment.background_color = Color("242b33")
	_world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_world.environment.ambient_light_color = Color("c3c6b9")
	_viewport.add_child(_world)
	for angle: Vector2 in [Vector2(-35,-35),Vector2(-25,140)]:
		var light: DirectionalLight3D = DirectionalLight3D.new()
		light.rotation_degrees = Vector3(angle.x, angle.y, 0)
		light.light_energy = 1.2 if angle.x == -35 else 0.5
		_viewport.add_child(light)
	var floor_mesh: MeshInstance3D = AssessorRig.part("Floor",Vector3(16,0.1,16),Vector3(0,-0.05,0),Color("464c4c"))
	_viewport.add_child(floor_mesh)
	for x: float in [-4,4]:
		_viewport.add_child(AssessorRig.part("ReferencePost",Vector3(0.15,1.8,0.15),Vector3(x,0.9,0),Color("bdab86")))
	_rig = AssessorRig.new()
	_rig.position.y = 3.5
	_viewport.add_child(_rig)
	_camera = Camera3D.new()
	_camera.fov = 58
	_viewport.add_child(_camera)
	for lighting: String in ["neutral","dim"]:
		_world.environment.ambient_light_energy = 0.65 if lighting == "neutral" else 0.18
		for state: Dictionary in [
			{"name":"front_idle","phase":"moving","tick":100,"camera":[6,1.62,0]},
			{"name":"front_windup_start","phase":"windup","tick":100,"camera":[6,1.62,0]},
			{"name":"front_windup_half","phase":"windup","tick":112,"camera":[6,1.62,0]},
			{"name":"front_windup_full","phase":"windup","tick":124,"camera":[6,1.62,0]},
			{"name":"flank_firing","phase":"firing","tick":112,"camera":[1,1.62,6]},
			{"name":"rear_recovery","phase":"recovery","tick":101,"camera":[-6,1.62,0]},
			{"name":"fan_overview","phase":"windup","tick":124,"camera":[5,7,5]},
			{"name":"supported_wreck","phase":"dead","tick":124,"camera":[5,1.62,3]},
		]:
			_rig.position.y = 0.0 if state.phase == "dead" else 3.5
			_rig.present({"phase":state.phase,"phase_started":100,"phase_ends":124},state.tick,0.0)
			_rig.advance(0.05)
			_camera.position = Vector3(state.camera[0],state.camera[1],state.camera[2])
			_camera.look_at(_rig.position + Vector3(0,0.55,0))
			await _capture(args[0],lighting+"_"+str(state.name),state)
	var strip: Image = Image.create(256*8,192*2,false,Image.FORMAT_RGB8)
	_rig.position.y = 3.5
	_camera.position = Vector3(6,1.62,2)
	_camera.look_at(_rig.position + Vector3(0,0.55,0))
	_world.environment.ambient_light_energy = 0.65
	for index: int in range(16):
		_rig.present({"phase":"windup","phase_started":100,"phase_ends":124},100+int(round(index*24.0/15.0)),0.0)
		_rig.advance(0.05)
		await process_frame
		await RenderingServer.frame_post_draw
		var tile: Image = _viewport.get_texture().get_image()
		tile.convert(Image.FORMAT_RGB8)
		tile.resize(256,192,Image.INTERPOLATE_NEAREST)
		assert(tile.get_format() == strip.get_format())
		strip.blit_rect(tile,Rect2i(0,0,256,192),Vector2i((index%8)*256,(index/8)*192))
	var strip_path: String = args[0].path_join("windup_strip.png")
	assert(strip.save_png(strip_path) == OK)
	var file: FileAccess = FileAccess.open(args[0].path_join("review.json"),FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"schema":1,"controlled_fixtures":true,"ordinary_input_acceptance":false,
		"rig_sha256":FileAccess.get_sha256("res://scripts/assessor_rig.gd"),"gpu":RenderingServer.get_video_adapter_name(),
		"renderer":RenderingServer.get_current_rendering_method(),"states":_rows,"windup_strip_sha256":FileAccess.get_sha256(strip_path)},"\t")+"\n")
	file.close()
	_viewport.free()
	await process_frame
	print("assessor_review: PASS, 16 bounded mechanical/lighting fixtures and one physical windup strip")
	quit(0)

func _capture(directory: String, name: String, state: Dictionary) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var path: String = directory.path_join(name+".png")
	var picture: Image = _viewport.get_texture().get_image()
	assert(not picture.is_empty() and picture.save_png(path) == OK)
	_rows.append({"name":name,"phase":state.phase,"tick":state.tick,"camera":state.camera,
		"feet":[_rig.position.x,_rig.position.y,_rig.position.z],"path":path,"sha256":FileAccess.get_sha256(path)})
