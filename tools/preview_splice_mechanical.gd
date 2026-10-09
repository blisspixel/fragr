extends SceneTree

const Rig = preload("res://../tools/splice_mechanical_rig.gd")
var _viewport: SubViewport
var _camera: Camera3D
var _environment: Environment
var _key: DirectionalLight3D
var _fill: DirectionalLight3D
var _out: String
var _rows: Array[Dictionary] = []

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 3 or not args[0].is_absolute_path() or not args[2].is_absolute_path() or DirAccess.make_dir_recursive_absolute(args[2]) != OK:
		_fail("absolute exact diagnostic input, candidate hash and output required")
		return
	_out = args[2]
	var rig: Dictionary = Rig.build(args[0], args[1])
	if rig.is_empty():
		_fail("pinned original/candidate did not load")
		return
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1024, 768)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var environment: WorldEnvironment = WorldEnvironment.new()
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.background_color = Color("222831")
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color("c1c8cd")
	_environment.ambient_light_energy = 0.55
	environment.environment = _environment
	_viewport.add_child(environment)
	_key = DirectionalLight3D.new()
	_key.rotation_degrees = Vector3(-35, -35, 0)
	_key.light_energy = 1.3
	_viewport.add_child(_key)
	_fill = DirectionalLight3D.new()
	_fill.rotation_degrees = Vector3(-20, 145, 0)
	_fill.light_energy = 0.65
	_viewport.add_child(_fill)
	var floor_mesh: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(4, 4)
	floor_mesh.mesh = plane
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color("353e45")
	material.roughness = 1.0
	floor_mesh.material_override = material
	_viewport.add_child(floor_mesh)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 2.15
	_viewport.add_child(_camera)
	var original: Node3D = Rig._load(Rig.RawAudit.SOURCE)
	if original == null:
		rig.root.free()
		_fail("original control cannot decode")
		return
	original.scale = Vector3.ONE * float(rig.scale)
	original.position.y = -float(rig.original_min) * float(rig.scale)
	_viewport.add_child(original)
	for angle: int in 4:
		_view(angle)
		if not await _capture("original_rest_%d" % angle, {"scope":"untouched original source control"}):
			return
	original.free()
	_viewport.add_child(rig.root)
	Rig.pose(rig, 0.0, false)
	for angle: int in 4:
		_view(angle)
		if not await _capture("candidate_rest_%d" % angle, Rig.measure(rig)):
			return
	for phase: float in [0.25, 0.75]:
		Rig.pose(rig, phase, true)
		for angle: int in 4:
			_view(angle)
			if not await _capture("walk_%03d_view_%d" % [int(phase * 100), angle], Rig.measure(rig)):
				return
	for phase: float in [0.0, 0.125, 0.5, 0.625]:
		_view(0)
		Rig.pose(rig, phase, true)
		if not await _capture("walk_front_%03d" % int(phase * 1000), Rig.measure(rig)):
			return
	for dim: bool in [false, true]:
		_environment.ambient_light_energy = 0.18 if dim else 0.55
		_key.light_energy = 0.35 if dim else 1.3
		_fill.light_energy = 0.1 if dim else 0.65
		Rig.pose(rig, 0.25, true)
		_view(0)
		_camera.size = 1.25
		_camera.position = Vector3(0.15, 0.95, 3.0)
		_camera.look_at(Vector3(0, 0.95, 0))
		if not await _capture("hip_wrist_close_" + ("dim" if dim else "neutral"), Rig.measure(rig)):
			return
		_camera.position = Vector3(-0.15, 0.95, -3.0)
		_camera.look_at(Vector3(0, 0.95, 0))
		if not await _capture("hip_wrist_close_back_" + ("dim" if dim else "neutral"), Rig.measure(rig)):
			return
		_camera.size = 4.0
		_camera.position = Vector3(0.5, 1.4, 5.0)
		_camera.look_at(Vector3(0, 0.9, 0))
		if not await _capture("distant_" + ("dim" if dim else "neutral"), Rig.measure(rig)):
			return
	_environment.ambient_light_energy = 0.55
	_key.light_energy = 1.3
	_fill.light_energy = 0.65
	_view(0)
	var started: int = Time.get_ticks_usec()
	for frame: int in 96:
		var phase: float = float(frame) / 48.0
		Rig.pose(rig, phase, true)
		await create_timer(1.0 / 24.0, false).timeout
		var measured: Dictionary = Rig.measure(rig)
		measured["phase"] = phase
		measured["elapsed_us"] = Time.get_ticks_usec() - started
		if not await _capture("motion_%03d" % frame, measured):
			return
	var file: FileAccess = FileAccess.open(_out.path_join("preview.json"), FileAccess.WRITE)
	if file == null:
		_fail("cannot retain original render receipt")
		return
	file.store_string(JSON.stringify({"schema":1, "scope":"source-only original and rigid candidate controls, no runtime selection or final art acceptance", "source_sha256":Rig.RawAudit.SHA, "regions_sha256":rig.candidate_sha256, "original_triangles":rig.original_triangles, "added_closure_triangles":rig.added_closure_triangles, "renderer":RenderingServer.get_current_rendering_method(), "adapter":RenderingServer.get_video_adapter_name(), "static_frames":26, "motion_frames":96, "frames":_rows}, "\t") + "\n")
	file.close()
	_viewport.free()
	await process_frame
	print("preview_splice_mechanical: PASS (26 static controls and 96 timed source-motion frames; inspection remains separate)")
	quit(0)

func _view(angle: int) -> void:
	_camera.size = 2.15
	_camera.position = Vector3(sin(angle * PI * 0.5 + 0.12) * 4, 1.12, cos(angle * PI * 0.5 + 0.12) * 4)
	_camera.look_at(Vector3(0, 0.9, 0))

func _capture(label: String, actual: Dictionary) -> bool:
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var picture: Image = _viewport.get_texture().get_image()
	var path: String = _out.path_join(label + ".png")
	if picture == null or picture.is_empty() or picture.save_png(path) != OK:
		_fail("empty or unwritable original-size source control")
		return false
	_rows.append({"file":label + ".png", "sha256":FileAccess.get_sha256(path), "actual":actual, "lighting":{"ambient":_environment.ambient_light_energy, "key":_key.light_energy, "fill":_fill.light_energy}})
	return true

func _fail(reason: String) -> void:
	push_error("preview_splice_mechanical: " + reason)
	quit(1)
