extends SceneTree

## Bakes the Enforcer atlas in the shared standing layout: 55 poses at eight
## directions in 160-pixel cells, fixed feet, nearest sampling. Armed gait
## cells hold committed charge poses. No other
## atlas is touched.

const Rig = preload("res://art/characters/enforcer_rig.gd")
const OUTPUT: String = "res://assets/characters/union/enforcer.png"
const MANIFEST: String = "res://assets/characters/union/enforcer-manifest.json"
const NORMALS: String = "res://assets/characters/union/enforcer_normals.png"
const NORMAL_SHADER: Shader = preload("res://art/models/normal_bake.gdshader")
var _bake_materials: Array[Material] = []
const SOURCES: Array[String] = ["res://art/characters/enforcer_rig.gd",
	"res://art/characters/enforcer_bake.gd", "res://art/models/enforcer_source.gd",
	"res://art/models/clerk_source.gd", "res://art/models/candidates/enforcer.glb",
	"res://art/models/normal_bake.gdshader",
	"res://art/characters/geometry.gd", "res://scripts/enemy_animation.gd"]

func _initialize() -> void:
	set_meta("fragr_automated", true)
	MouseCapture.release()
	call_deferred("bake")

func bake() -> void:
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
	var rig: RefCounted = Rig.new()
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
				# Actual Fists gait uses unarmed walk; its armed row carries charge.
				if action == "walk" and not bool(clip["unarmed"]):
					action = "charge"
				elif action == "seated":
					action = "idle"
				var model: Node3D = rig.build_enforcer(action, progress, bool(clip["unarmed"]))
				_albedo(model)
				viewport.add_child(model)
				model.rotation_degrees.y = direction * 45.0
				await process_frame
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				var capture: Image = viewport.get_texture().get_image()
				capture.convert(Image.FORMAT_RGBA8)
				var rect: Rect2i = capture.get_used_rect()
				if rect.size == Vector2i.ZERO or rect.position.x == 0 or rect.position.y == 0 \
					or rect.end.x >= EnemyAnimation.TILE or rect.end.y >= EnemyAnimation.TILE:
					push_error("enforcer_bake: empty or clipped %s %d/%d rect %s" % [action, direction, index, rect])
					quit(1)
					return
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
	if atlas.save_png(ProjectSettings.globalize_path(OUTPUT)) != OK:
		push_error("enforcer_bake: could not write atlas")
		quit(1)
		return
	if normals.save_png(ProjectSettings.globalize_path(NORMALS)) != OK:
		push_error("enforcer_bake: could not write normals")
		quit(1)
		return
	var sources: Dictionary[String, String] = {}
	for path: String in SOURCES:
		sources[path] = FileAccess.get_sha256(path)
	var receipt: FileAccess = FileAccess.open(MANIFEST, FileAccess.WRITE)
	if receipt == null or not receipt.store_string(JSON.stringify({
		"schema":1, "engine":Engine.get_version_info()["string"],
		"model":"Stylized human powered armor with sampled gait, committed charge posture, shoulder-drop windup and issued vent tell; armed gait cells hold charge",
		"format":"RGBA8 PNG, nearest sampling, no mipmaps",
		"sources":sources, "file":"enforcer.png", "sha256":FileAccess.get_sha256(OUTPUT),
		"normals_file":"enforcer_normals.png", "normals_sha256":FileAccess.get_sha256(NORMALS),
		"tile_pixels":EnemyAnimation.TILE, "poses":EnemyAnimation.poses(),
		"directions":EnemyAnimation.DIRECTIONS, "columns":EnemyAnimation.COLUMNS,
		"rows":EnemyAnimation.rows(), "clips":EnemyAnimation.CLIPS
	}, "\t") + "\n"):
		push_error("enforcer_bake: could not write receipt")
		quit(1)
		return
	receipt.close()
	viewport.queue_free()
	await process_frame
	await RenderingServer.frame_post_draw
	print("enforcer_bake: PASS")
	quit()

func _albedo(node: Node) -> void:
	if node is MeshInstance3D:
		for surface: int in range(node.mesh.get_surface_count()):
			var original: StandardMaterial3D = node.get_active_material(surface) as StandardMaterial3D
			if original != null:
				var material: StandardMaterial3D = original.duplicate()
				material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				material.emission_enabled = false
				_bake_materials.append(material)
				node.set_surface_override_material(surface, material)
	for child: Node in node.get_children():
		_albedo(child)

func _normal(node: Node) -> void:
	if node is MeshInstance3D:
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = NORMAL_SHADER
		node.material_override = material
	for child: Node in node.get_children():
		_normal(child)
