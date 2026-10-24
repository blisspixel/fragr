extends SceneTree

## Art style trial, Treatment B: extends the shipped directional bake (the
## Clerk/Sweeper/Auditor pipeline in art/characters/bake.gd) to the free human
## and the free synthetic (in the trial's personal livery, trial_livery.gd).
## Same 55 poses, eight directions, 160 pixel cells, ortho field, bake light
## and paired view normals. Writes only to the absolute output directory
## given; never touches client/assets.
##
## godot --path client --rendering-driver opengl3 --windowed --audio-driver Dummy \
##   --script res://art/style_trial/trial_bake.gd -- <abs out dir> human synthetic

const TrialPose = preload("res://art/style_trial/trial_pose_source.gd")
const TrialLivery = preload("res://art/style_trial/trial_livery.gd")
const NORMAL_SHADER: Shader = preload("res://art/models/normal_bake.gdshader")
var _bake_materials: Array[Material] = []

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("bake")

func bake() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2 or not args[0].is_absolute_path():
		push_error("trial_bake: require <absolute out dir> <unit>...")
		quit(1)
		return
	var out: String = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(640, 480)
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i.ONE * EnemyAnimation.TILE
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("d1ccc1")
	environment.environment.ambient_light_energy = 0.45
	viewport.add_child(environment)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-25, -30, 0)
	light.light_energy = 1.3
	viewport.add_child(light)
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = EnemyAnimation.VIEW_SIZE
	viewport.add_child(camera)
	camera.position = Vector3(0, EnemyAnimation.CENTRE_HEIGHT, 5)
	camera.look_at(Vector3(0, EnemyAnimation.CENTRE_HEIGHT, 0))
	var receipt: Dictionary = {"schema": 1, "engine": Engine.get_version_info()["string"],
		"renderer": RenderingServer.get_current_rendering_method(), "video_adapter": RenderingServer.get_video_adapter_name(),
		"tile_pixels": EnemyAnimation.TILE, "poses": EnemyAnimation.poses(), "directions": EnemyAnimation.DIRECTIONS,
		"columns": EnemyAnimation.COLUMNS, "rows": EnemyAnimation.rows(), "units": {}}
	var started: int = Time.get_ticks_msec()
	for unit_index: int in range(1, args.size()):
		var unit: String = args[unit_index]
		if not TrialPose.SOURCES.has(unit):
			push_error("trial_bake: unknown unit " + unit)
			quit(1)
			return
		var source: RefCounted = TrialPose.new(unit)
		var atlas: Image = Image.create(EnemyAnimation.COLUMNS * EnemyAnimation.TILE,
			EnemyAnimation.rows() * EnemyAnimation.TILE, false, Image.FORMAT_RGBA8)
		var normals: Image = Image.create(atlas.get_width(), atlas.get_height(), false, Image.FORMAT_RGBA8)
		for direction: int in range(EnemyAnimation.DIRECTIONS):
			var pose: int = 0
			for clip: Dictionary in EnemyAnimation.CLIPS:
				var count: int = int(clip["count"])
				for index: int in range(count):
					var progress: float = float(index) / maxf(1.0, float(count - 1))
					if clip["action"] == "walk":
						progress = float(index) / count
					var model: Node3D = source.call("build_pose", str(clip["action"]), progress, bool(clip["unarmed"])) as Node3D
					viewport.add_child(model)
					if unit == "synthetic":
						TrialLivery.apply(model)
					_albedo(model)
					model.rotation_degrees.y = direction * 45.0
					await process_frame
					await RenderingServer.frame_post_draw
					await RenderingServer.frame_post_draw
					var capture: Image = viewport.get_texture().get_image()
					capture.convert(Image.FORMAT_RGBA8)
					var rect: Rect2i = capture.get_used_rect()
					if rect.size == Vector2i.ZERO or rect.position.x == 0 or rect.position.y == 0 \
						or rect.end.x >= EnemyAnimation.TILE or rect.end.y >= EnemyAnimation.TILE:
						push_warning("trial_bake: empty or clipped %s %s %d/%d rect %s" % [unit, clip["action"], direction, index, rect])
					var frame: int = direction * EnemyAnimation.poses() + pose
					var cell: Vector2i = Vector2i(frame % EnemyAnimation.COLUMNS,
						floori(float(frame) / EnemyAnimation.COLUMNS)) * EnemyAnimation.TILE
					atlas.blit_rect(capture, Rect2i(Vector2i.ZERO, viewport.size), cell)
					_normal(model)
					await RenderingServer.frame_post_draw
					await RenderingServer.frame_post_draw
					var normal_capture: Image = viewport.get_texture().get_image()
					normal_capture.convert(Image.FORMAT_RGBA8)
					normals.blit_rect(normal_capture, Rect2i(Vector2i.ZERO, viewport.size), cell)
					pose += 1
					model.queue_free()
					await process_frame
		var albedo_path: String = out.path_join(unit + ".png")
		var normal_path: String = out.path_join(unit + "_normals.png")
		if atlas.save_png(albedo_path) != OK or normals.save_png(normal_path) != OK:
			push_error("trial_bake: could not write " + unit)
			quit(1)
			return
		receipt["units"][unit] = {"source": TrialPose.SOURCES[unit], "source_sha256": FileAccess.get_sha256(TrialPose.SOURCES[unit]),
			"albedo": unit + ".png", "albedo_sha256": FileAccess.get_sha256(albedo_path),
			"normals": unit + "_normals.png", "normals_sha256": FileAccess.get_sha256(normal_path)}
		print("trial_bake: wrote ", unit)
	receipt["bake_seconds"] = (Time.get_ticks_msec() - started) / 1000.0
	var scripts: Dictionary = {}
	for path: String in ["res://art/style_trial/trial_bake.gd", "res://art/style_trial/trial_pose_source.gd",
			"res://art/style_trial/trial_livery.gd", "res://art/models/clerk_source.gd", "res://art/characters/geometry.gd",
			"res://art/models/normal_bake.gdshader", "res://scripts/enemy_animation.gd"]:
		scripts[path] = FileAccess.get_sha256(path)
	receipt["scripts"] = scripts
	var file: FileAccess = FileAccess.open(out.path_join("bake-receipt.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(receipt, "\t") + "\n")
		file.close()
	viewport.queue_free()
	await process_frame
	print("trial_bake: PASS")
	quit()

func _albedo(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_node: MeshInstance3D = node as MeshInstance3D
		var original: StandardMaterial3D = mesh_node.material_override as StandardMaterial3D
		if original != null:
			mesh_node.material_override = _unlit(original)
		else:
			for surface: int in range(mesh_node.mesh.get_surface_count()):
				var material: StandardMaterial3D = mesh_node.get_active_material(surface) as StandardMaterial3D
				if material != null:
					mesh_node.set_surface_override_material(surface, _unlit(material))
	for child: Node in node.get_children():
		_albedo(child)

func _unlit(original: StandardMaterial3D) -> StandardMaterial3D:
	var material: StandardMaterial3D = original.duplicate() as StandardMaterial3D
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = false
	_bake_materials.append(material)
	return material

func _normal(node: Node) -> void:
	if node is MeshInstance3D:
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = NORMAL_SHADER
		(node as MeshInstance3D).material_override = material
	for child: Node in node.get_children():
		_normal(child)
