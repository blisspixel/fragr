extends SceneTree

## Developer source inspection only. No network or simulation callbacks.
const Source = preload("res://art/models/enforcer_source.gd")
const SIZE: int = 384
const POSES: Array[Dictionary] = [
	{"action":"idle", "progress":0.0},
	{"action":"raise", "progress":1.0},
	{"action":"charge", "progress":0.0},
	{"action":"charge", "progress":0.5},
	{"action":"recover", "progress":0.5},
	{"action":"recover", "progress":1.0},
	{"action":"hit", "progress":0.0},
	{"action":"death", "progress":1.0},
]
const VIEWS: Array[float] = [0.0, PI * 0.5, PI]

func _initialize() -> void:
	set_meta("fragr_automated", true)
	MouseCapture.release()
	_run.call_deferred()

func _run() -> void:
	var directory: String = OS.get_environment("FRAGR_ENFORCER_SOURCE_CAPTURE")
	if not directory.is_absolute_path() or DirAccess.make_dir_recursive_absolute(directory) != OK:
		push_error("qa_enforcer_source: require owned absolute capture directory")
		quit(1)
		return
	root.size = Vector2i(640, 480)
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i.ONE * SIZE
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("d1ccc1")
	environment.environment.ambient_light_energy = 0.5
	viewport.add_child(environment)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-25, -30, 0)
	light.light_energy = 1.3
	viewport.add_child(light)
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = EnemyAnimation.VIEW_SIZE
	camera.position = Vector3(0, EnemyAnimation.CENTRE_HEIGHT, 5)
	viewport.add_child(camera)
	camera.look_at(Vector3(0, EnemyAnimation.CENTRE_HEIGHT, 0))
	var source: RefCounted = Source.new()
	var sheet: Image = Image.create(SIZE * POSES.size(), SIZE * VIEWS.size(), false, Image.FORMAT_RGBA8)
	var entries: Array[Dictionary] = []
	for view: int in range(VIEWS.size()):
		for pose: int in range(POSES.size()):
			var spec: Dictionary = POSES[pose]
			var model: Node3D = source.build_pose(str(spec["action"]), float(spec["progress"]), true)
			viewport.add_child(model)
			model.rotation.y = VIEWS[view]
			await process_frame
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var capture: Image = viewport.get_texture().get_image()
			capture.convert(Image.FORMAT_RGBA8)
			var used: Rect2i = capture.get_used_rect()
			if used.size == Vector2i.ZERO or used.position.x <= 0 or used.position.y <= 0 \
				or used.end.x >= SIZE or used.end.y >= SIZE:
				push_error("qa_enforcer_source: clipped source pose " + str(spec))
				model.free()
				quit(1)
				return
			var filename: String = "pose-%02d-view-%d.png" % [pose, view]
			if capture.save_png(directory.path_join(filename)) != OK:
				push_error("qa_enforcer_source: capture write failed")
				model.free()
				quit(1)
				return
			sheet.blit_rect(capture, Rect2i(Vector2i.ZERO, viewport.size), Vector2i(pose, view) * SIZE)
			entries.append({"file":filename, "action":spec["action"], "progress":spec["progress"],
				"view":view, "used_rect":[used.position.x, used.position.y, used.size.x, used.size.y]})
			model.free()
			await process_frame
	if sheet.save_png(directory.path_join("pose-sheet.png")) != OK:
		push_error("qa_enforcer_source: sheet write failed")
		quit(1)
		return
	var receipt: FileAccess = FileAccess.open(directory.path_join("manifest.json"), FileAccess.WRITE)
	if receipt == null or not receipt.store_string(JSON.stringify({"schema":1,
		"engine":Engine.get_version_info()["string"], "entries":entries,
		"source_sha256":FileAccess.get_sha256(Source.ENFORCER_SOURCE),
		"pose_sha256":FileAccess.get_sha256("res://art/models/enforcer_source.gd"),
		"helper_sha256":FileAccess.get_sha256("res://art/models/clerk_source.gd"),
		"inspection_sha256":FileAccess.get_sha256("res://scripts/qa_enforcer_source.gd")}, "\t") + "\n"):
		push_error("qa_enforcer_source: receipt write failed")
		quit(1)
		return
	receipt.close()
	viewport.free()
	await process_frame
	await RenderingServer.frame_post_draw
	print("qa_enforcer_source: PASS 24 actual source poses, unclipped")
	quit(0)
