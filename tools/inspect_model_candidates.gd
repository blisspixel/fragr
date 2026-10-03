extends SceneTree

# Offline inspection only. Does not select runtime assets or create collision.
var _viewport: SubViewport
var _camera: Camera3D
var _out: String
var _rows: Array[Dictionary] = []

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2 or not DirAccess.dir_exists_absolute(args[0]):
		_fail("require existing model directory and output directory")
		return
	_out = args[1]
	if DirAccess.make_dir_recursive_absolute(_out) != OK:
		_fail("cannot create inspection directory")
		return
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1200, 900)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var world: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("222831")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c1c8cd")
	environment.ambient_light_energy = 0.55
	world.environment = environment
	_viewport.add_child(world)
	for spec: Vector3 in [Vector3(-35, -35, 1.6), Vector3(-20, 145, 0.7)]:
		var light: DirectionalLight3D = DirectionalLight3D.new()
		light.rotation_degrees = Vector3(spec.x, spec.y, 0)
		light.light_energy = spec.z
		_viewport.add_child(light)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_viewport.add_child(_camera)
	var names: PackedStringArray = DirAccess.get_files_at(args[0])
	names.sort()
	for name: String in names:
		if name.get_extension().to_lower() != "glb":
			continue
		if _rows.size() >= 32:
			_fail("model batch exceeds 32 candidates")
			return
		if not await _inspect(args[0].path_join(name), name.get_basename()):
			return
	if _rows.is_empty():
		_fail("no GLB candidates")
		return
	var file: FileAccess = FileAccess.open(_out.path_join("inspection.json"), FileAccess.WRITE)
	if file == null:
		_fail("cannot write inspection receipt")
		return
	file.store_string(JSON.stringify({"schema": 1, "renderer": RenderingServer.get_current_rendering_method(), "models": _rows}, "\t") + "\n")
	file.close()
	print("model_candidates: PASS (%d imported and rendered; art acceptance is separate)" % _rows.size())
	quit(0)

func _inspect(path: String, name: String) -> bool:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.size() < 20 or bytes.size() > 64 * 1024 * 1024:
		_fail("candidate size outside bounds")
		return false
	var document: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	if document.append_from_file(path, state) != OK:
		_fail("GLB import failed: " + name)
		return false
	var model: Node3D = document.generate_scene(state)
	if model == null:
		_fail("GLB scene generation failed: " + name)
		return false
	_viewport.add_child(model)
	var stats: Dictionary = {"meshes": 0, "triangles": 0, "vertices": 0, "bones": 0, "animations": [], "materials": []}
	var bounds: AABB = _scan(model, stats)
	if stats["meshes"] == 0 or bounds.size.length() <= 0.001:
		model.free()
		_fail("model has no inspectable mesh: " + name)
		return false
	var centre: Vector3 = bounds.get_center()
	var extent: float = maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	_camera.size = extent * 1.35
	for index: int in range(4):
		var angle: float = float(index) * PI * 0.5 + 0.35
		_camera.position = centre + Vector3(sin(angle) * extent * 3.0, extent * 0.2, cos(angle) * extent * 3.0)
		_camera.look_at(centre)
		if not await _capture(name + "-view-%d.png" % index):
			model.free()
			return false
	var players: Array[Node] = model.find_children("*", "AnimationPlayer", true, false)
	for candidate: Node in players:
		var player: AnimationPlayer = candidate as AnimationPlayer
		for clip: StringName in player.get_animation_list():
			if clip == &"RESET":
				continue
			player.play(clip)
			var animation: Animation = player.get_animation(clip)
			for sample: int in range(4):
				player.seek(animation.length * float(sample) / 4.0, true)
				if not await _capture(name + "-motion-%d.png" % sample):
					model.free()
					return false
			player.stop()
			break
	_rows.append({"name": name, "sha256": FileAccess.get_sha256(path), "bytes": bytes.size(),
		"bounds": {"position": [bounds.position.x, bounds.position.y, bounds.position.z], "size": [bounds.size.x, bounds.size.y, bounds.size.z]}, "stats": stats})
	model.free()
	return true

func _scan(node: Node, stats: Dictionary) -> AABB:
	var bounds: AABB = AABB()
	var has_bounds: bool = false
	if node is MeshInstance3D and node.mesh != null:
		stats["meshes"] += 1
		bounds = node.global_transform * node.mesh.get_aabb()
		has_bounds = true
		for surface: int in range(node.mesh.get_surface_count()):
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			var vertices: Variant = arrays[Mesh.ARRAY_VERTEX]
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			if vertices is PackedVector3Array:
				stats["vertices"] += vertices.size()
				if node.mesh.surface_get_primitive_type(surface) == Mesh.PRIMITIVE_TRIANGLES:
					stats["triangles"] += (indices.size() if indices is PackedInt32Array and not indices.is_empty() else vertices.size()) / 3
			var material: Material = node.get_active_material(surface)
			if material is StandardMaterial3D:
				var albedo: Texture2D = material.albedo_texture
				stats["materials"].append({"normal_enabled": material.normal_enabled,
					"albedo_size": [albedo.get_width(), albedo.get_height()] if albedo != null else [],
					"metallic_map": material.metallic_texture != null, "roughness_map": material.roughness_texture != null})
	if node is Skeleton3D:
		stats["bones"] += node.get_bone_count()
	if node is AnimationPlayer:
		for clip: StringName in node.get_animation_list():
			stats["animations"].append({"name": String(clip), "length": node.get_animation(clip).length})
	for child: Node in node.get_children():
		var child_bounds: AABB = _scan(child, stats)
		if child_bounds.size.length() > 0.001:
			bounds = bounds.merge(child_bounds) if has_bounds else child_bounds
			has_bounds = true
	return bounds

func _capture(name: String) -> bool:
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if _viewport.get_texture().get_image().save_png(_out.path_join(name)) != OK:
		_fail("cannot write candidate render")
		return false
	return true

func _fail(message: String) -> void:
	push_error("model_candidates: " + message)
	quit(1)
