extends SceneTree

const Source = preload("res://art/models/tern_source.gd")
var _viewport: SubViewport
var _camera: Camera3D
var _environment: Environment
var _lights: Array[DirectionalLight3D] = []
var _out: String
var _rows: Array[Dictionary] = []
var _sheet: Image
var _sheet_index: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2 or DirAccess.make_dir_recursive_absolute(args[1]) != OK:
		_fail("require original walking GLB and output directory")
		return
	_out = args[1]
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1024, 768)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var world: WorldEnvironment = WorldEnvironment.new()
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.background_color = Color("222831")
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color("c1c8cd")
	world.environment = _environment
	_viewport.add_child(world)
	for angles: Vector2 in [Vector2(-35, -35), Vector2(-20, 145)]:
		var light: DirectionalLight3D = DirectionalLight3D.new()
		light.rotation_degrees = Vector3(angles.x, angles.y, 0)
		_viewport.add_child(light)
		_lights.append(light)
	var floor_mesh: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(4.0, 4.0)
	floor_mesh.mesh = plane
	var floor_material: StandardMaterial3D = StandardMaterial3D.new()
	floor_material.albedo_color = Color("353e45")
	floor_material.roughness = 1.0
	floor_mesh.material_override = floor_material
	_viewport.add_child(floor_mesh)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 2.15
	_viewport.add_child(_camera)
	_sheet = Image.create(256 * 8, 192 * 4, false, Image.FORMAT_RGB8)
	var source: RefCounted = Source.new()
	for lighting: String in ["neutral", "dim"]:
		_environment.ambient_light_energy = 0.55 if lighting == "neutral" else 0.16
		_lights[0].light_energy = 1.6 if lighting == "neutral" else 0.35
		_lights[1].light_energy = 0.7 if lighting == "neutral" else 0.12
		for kind: String in ["original", "prepared"]:
			var figure: Node3D = _load_original(args[0]) if kind == "original" else source.build_pose("rest", 0.0, true)
			if figure == null:
				_fail("cannot import source control")
				return
			_viewport.add_child(figure)
			for angle: int in range(4):
				_camera.size = 2.15
				_camera.position = Vector3(sin(angle * PI * 0.5 + 0.15) * 4.0, 1.12, cos(angle * PI * 0.5 + 0.15) * 4.0)
				_camera.look_at(Vector3(0, 0.90, 0))
				if not await _capture("%s_%s_rest_%d" % [lighting, kind, angle], figure, true):
					return
			_camera.size = 0.48
			_camera.position = Vector3(0.06, 1.72, 3.0)
			_camera.look_at(Vector3(0.0, 1.68, 0.0))
			if not await _capture("%s_%s_head" % [lighting, kind], figure, false):
				return
			figure.free()
	_environment.ambient_light_energy = 0.55
	_lights[0].light_energy = 1.6
	_lights[1].light_energy = 0.7
	for phase: int in range(8):
		var figure: Node3D = source.build_pose("walk", float(phase) / 8.0, true)
		_viewport.add_child(figure)
		_camera.size = 2.15
		_camera.position = Vector3(3.0, 1.12, 3.0)
		_camera.look_at(Vector3(0, 0.90, 0))
		if not await _capture("neutral_prepared_walk_%d" % phase, figure, true):
			return
		figure.free()
	var calm: Node3D = source.build_pose("calm", 0.0, true)
	_viewport.add_child(calm)
	for angle: int in range(4):
		_camera.position = Vector3(sin(angle * PI * 0.5 + 0.15) * 4.0, 1.12, cos(angle * PI * 0.5 + 0.15) * 4.0)
		_camera.look_at(Vector3(0, 0.90, 0))
		if not await _capture("neutral_prepared_calm_%d" % angle, calm, true):
			return
	calm.free()
	if _sheet.save_png(_out.path_join("overview.png")) != OK:
		_fail("cannot save overview")
		return
	var file: FileAccess = FileAccess.open(_out.path_join("preview.json"), FileAccess.WRITE)
	if file == null:
		_fail("cannot save preview receipt")
		return
	file.store_string(JSON.stringify({"schema": 1, "runtime_selected": false,
		"renderer": RenderingServer.get_current_rendering_method(),
		"video_adapter": RenderingServer.get_video_adapter_name(),
		"source_sha256": FileAccess.get_sha256(args[0]),
		"candidate_sha256": FileAccess.get_sha256("res://art/models/candidates/tern.glb"),
		"frames": _rows, "overview_sha256": FileAccess.get_sha256(_out.path_join("overview.png"))}, "\t") + "\n")
	file.close()
	_viewport.free()
	await process_frame
	print("preview_tern_source: PASS (32 original/prepared angle, light, head and gait views; source-only acceptance)")
	quit(0)

func _load_original(path: String) -> Node3D:
	var document: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	return document.generate_scene(state) if document.append_from_file(path, state) == OK else null

func _capture(label: String, figure: Node3D, in_sheet: bool) -> bool:
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var picture: Image = _viewport.get_texture().get_image()
	var path: String = _out.path_join(label + ".png")
	if picture == null or picture.is_empty() or picture.save_png(path) != OK:
		_fail("empty or unwritable preview " + label)
		return false
	var points: PackedVector3Array = Source.weighted_points(figure)
	if points.size() != 19106:
		_fail("preview lost actual weighted geometry")
		return false
	var bounds: AABB = AABB(points[0], Vector3.ZERO)
	for point: Vector3 in points:
		bounds = bounds.expand(point)
	_rows.append({"file": label + ".png", "sha256": FileAccess.get_sha256(path),
		"weighted_min_y": bounds.position.y, "weighted_height": bounds.size.y,
		"vertices": points.size()})
	if in_sheet:
		picture.convert(Image.FORMAT_RGB8)
		picture.resize(256, 192, Image.INTERPOLATE_LANCZOS)
		_sheet.blit_rect(picture, Rect2i(0, 0, 256, 192), Vector2i((_sheet_index % 8) * 256, int(_sheet_index / 8) * 192))
		_sheet_index += 1
	return true

func _fail(message: String) -> void:
	push_error("preview_tern_source: " + message)
	quit(1)
