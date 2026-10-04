extends SceneTree

const Rig = preload("res://art/characters/machines.gd")
const SweeperSource = preload("res://art/models/sweeper_skinned_source.gd")
const ClerkSource = preload("res://art/models/clerk_source.gd")
const NORMAL_SHADER: Shader = preload("res://art/models/normal_bake.gdshader")
const KINDS: Dictionary[String, Dictionary] = {
	"clerk": {"model": "skinned human security source with authored combat poses and paired view normals",
		"brief": "Stylized angular human face, black peaked service cap and high-collar uniform, dark steel plates and a clear red band with a fictional registry seal."},
	"sweeper": {"model": "skinned angular issued bot with two-handed rifle poses and paired view normals",
		"brief": "Dark steel shells, recessed red optical slit, exposed mechanical joints and red issue panels. Earlier rigid GLB remains the separate mechanical library."},
	"heavy_sweeper": {"model": "articulated heavy bot rig",
		"brief": "Broad armored chassis, head sunk between wide pauldrons, ammunition drum, rotary cannon and ember tell lamps."},
	"turret": {"model": "fixed turret rig",
		"brief": "Braced column with a rotating bone housing, rail barrel with red charge coils and a red sensor lamp."},
}
const OUTPUT: String = "res://assets/characters/union/"
var _bake_materials: Array[Material] = []

func _initialize() -> void:
	set_meta("fragr_automated", true)
	MouseCapture.release()
	call_deferred("bake")

func bake() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var selected: String = ""
	var retained: Array[Dictionary] = []
	var retained_receipt: Dictionary = {}
	var retained_kinds: Array[String] = []
	if not args.is_empty():
		if args.size() != 2 or args[0] != "--kind" or not KINDS.has(args[1]):
			push_error("character_bake: require no arguments or --kind with a registered cast")
			quit(1)
			return
		selected = args[1]
		var prior_path: String = OUTPUT + "manifest.json"
		var prior: Variant = JSON.parse_string(FileAccess.get_file_as_string(prior_path))
		if not prior is Dictionary or not prior.get("entries") is Array or not prior.get("sources") is Dictionary:
			push_error("character_bake: partial bake requires an existing receipt")
			quit(1)
			return
		retained_receipt = {"sha256": FileAccess.get_sha256(prior_path), "sources": prior["sources"]}
		var expected_files: Array[String] = []
		for kind: String in KINDS:
			expected_files.append(kind + ".png")
			if kind in ["clerk", "sweeper"]:
				expected_files.append(kind + "_normals.png")
		var seen: Dictionary[String, bool] = {}
		for entry: Variant in prior["entries"]:
			if not entry is Dictionary or not entry.get("file") is String or not entry.get("sha256") is String:
				push_error("character_bake: invalid retained entry")
				quit(1)
				return
			var file: String = entry["file"]
			if not expected_files.has(file) or seen.has(file):
				push_error("character_bake: unregistered or duplicate retained output")
				quit(1)
				return
			seen[file] = true
			if file in [selected + ".png", selected + "_normals.png"]:
				continue
			if file.get_file() != file or FileAccess.get_sha256(OUTPUT + file) != entry["sha256"]:
				push_error("character_bake: retained output disagrees with its receipt")
				quit(1)
				return
			retained.append(entry)
		if seen.size() != expected_files.size():
			push_error("character_bake: existing receipt omits a registered cast output")
			quit(1)
			return
		for kind: String in KINDS:
			if kind != selected:
				retained_kinds.append(kind)
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
	var display: TextureRect = TextureRect.new()
	display.texture = viewport.get_texture()
	display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	display.size = Vector2(480, 480)
	root.add_child(display)
	var rig: RefCounted = Rig.new()
	var sweeper: RefCounted = SweeperSource.new()
	var clerk: RefCounted = ClerkSource.new()
	var entries: Array[Dictionary] = retained.duplicate()
	var rendered_kinds: Array[String] = []
	for kind: String in KINDS:
		if not selected.is_empty() and kind != selected:
			continue
		rendered_kinds.append(kind)
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
					var action: String = str(clip["action"])
					var unarmed: bool = bool(clip["unarmed"])
					var model: Node3D = sweeper.build_pose(action, progress, unarmed) if kind == "sweeper" else \
						(clerk.build_pose(action, progress, unarmed) if kind == "clerk" else rig.build_machine(kind, action, progress, unarmed))
					viewport.add_child(model)
					if kind in ["sweeper", "clerk"]:
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
						push_error("character_bake: empty or clipped %s %s %d/%d rect %s" % [kind, clip["action"], direction, index, rect])
						quit(1)
						return
					var frame: int = direction * EnemyAnimation.poses() + pose
					var cell: Vector2i = Vector2i(frame % EnemyAnimation.COLUMNS,
						floori(float(frame) / EnemyAnimation.COLUMNS)) * EnemyAnimation.TILE
					atlas.blit_rect(capture, Rect2i(Vector2i.ZERO, viewport.size), cell)
					if kind in ["sweeper", "clerk"]:
						_normal(model)
						await RenderingServer.frame_post_draw
						await RenderingServer.frame_post_draw
						var normal_capture: Image = viewport.get_texture().get_image()
						normal_capture.convert(Image.FORMAT_RGBA8)
						normals.blit_rect(normal_capture, Rect2i(Vector2i.ZERO, viewport.size), cell)
					pose += 1
					model.queue_free()
					await process_frame
		var destination: String = OUTPUT + kind + ".png"
		if atlas.save_png(destination) != OK:
			push_error("character_bake: could not write " + destination)
			quit(1)
			return
		entries.append({"file": kind + ".png", "sha256": FileAccess.get_sha256(destination),
			"model": KINDS[kind]["model"], "brief": KINDS[kind]["brief"]})
		if kind in ["sweeper", "clerk"]:
			var normal_path: String = OUTPUT + kind + "_normals.png"
			if normals.save_png(normal_path) != OK:
				push_error("character_bake: could not write normal atlas")
				quit(1)
				return
			entries.append({"file": kind + "_normals.png", "sha256": FileAccess.get_sha256(normal_path), "model": "paired normal atlas", "brief": "Same eight directions and phase cells as the matching albedo."})
		print("character_bake: wrote ", kind)
	var sources: Dictionary[String, String] = {}
	for source: String in ["res://art/characters/geometry.gd", "res://art/characters/rig.gd",
		"res://art/characters/machines.gd", "res://art/characters/bake.gd", "res://scripts/enemy_animation.gd",
		"res://scripts/model_geometry.gd", "res://art/models/sweeper_source.gd", "res://art/models/normal_bake.gdshader",
		"res://art/models/sweeper_skinned_source.gd", "res://art/models/candidates/sweeper.glb", "res://art/models/candidates/sweeper.glb.import",
		"res://art/models/clerk_source.gd", "res://art/models/candidates/clerk.glb",
		"res://assets/models/finishes/wood.png", "res://assets/models/finishes/metal.png", "res://assets/models/finishes/enamel.png"]:
		sources[source] = FileAccess.get_sha256(source)
	var manifest: FileAccess = FileAccess.open(OUTPUT + "manifest.json", FileAccess.WRITE)
	if manifest == null or not manifest.store_string(JSON.stringify({
		"schema":1, "engine":Engine.get_version_info()["string"],
		"format":"RGBA8 PNG, nearest sampling, no mipmaps", "sources":sources,
		"tile_pixels":EnemyAnimation.TILE, "poses":EnemyAnimation.poses(),
		"directions":EnemyAnimation.DIRECTIONS, "columns":EnemyAnimation.COLUMNS,
		"rows":EnemyAnimation.rows(), "clips":EnemyAnimation.CLIPS, "entries":entries,
		"rendered_kinds":rendered_kinds, "retained_kinds":retained_kinds, "retained_receipt":retained_receipt
	}, "\t") + "\n"):
		push_error("character_bake: could not write manifest")
		quit(1)
		return
	manifest.close()
	viewport.queue_free()
	display.queue_free()
	await process_frame
	await RenderingServer.frame_post_draw
	print("character_bake: PASS (%d rendered, %d retained atlases)" % [entries.size() - retained.size(), retained.size()])
	quit()

func _albedo(node: Node) -> void:
	if node is MeshInstance3D:
		var original: StandardMaterial3D = node.material_override as StandardMaterial3D
		if original != null:
			node.material_override = _unlit(original)
		else:
			for surface: int in range(node.mesh.get_surface_count()):
				var material: StandardMaterial3D = node.get_active_material(surface) as StandardMaterial3D
				if material != null:
					node.set_surface_override_material(surface, _unlit(material))
	for child: Node in node.get_children():
		_albedo(child)

func _unlit(original: StandardMaterial3D) -> StandardMaterial3D:
	var material: StandardMaterial3D = original.duplicate()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = false
	_bake_materials.append(material)
	return material

func _normal(node: Node) -> void:
	if node is MeshInstance3D:
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = NORMAL_SHADER
		node.material_override = material
	for child: Node in node.get_children():
		_normal(child)
