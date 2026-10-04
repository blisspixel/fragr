extends SceneTree

const Facility = preload("res://scripts/facility_geometry.gd")
const Sweeper = preload("res://art/models/sweeper_source.gd")
const Shotgun = preload("res://art/models/shotgun_source.gd")
var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("test_model_assets: " + message)

func _run() -> void:
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/manifest.json"))
	_check(manifest is Dictionary and manifest.get("models") is Array and manifest.get("sources") is Dictionary, "model receipt describes source and exports")
	if not manifest is Dictionary:
		quit(1)
		return
	for source: String in manifest["sources"]:
		_check(FileAccess.get_sha256(source) == manifest["sources"][source], "source changed without re-export: " + source)
	_check(manifest["models"].size() >= 8, "weapon, articulated body and modular fixtures exist")
	for entry: Dictionary in manifest["models"]:
		var path: String = "res://assets/models/" + entry["file"]
		_check(FileAccess.get_sha256(path) == entry["sha256"], "export hash agrees with receipt")
		var document: GLTFDocument = GLTFDocument.new()
		var state: GLTFState = GLTFState.new()
		_check(document.append_from_file(path, state) == OK, "engine imports complete GLB: " + path)
		var model: Node3D = document.generate_scene(state) as Node3D
		_check(model != null, "GLB produces a scene")
		if model == null:
			continue
		root.add_child(model)
		_check(not model.find_children("*", "MeshInstance3D", true, false).is_empty(), "export contains real surfaces")
		_check(model.find_children("*", "CollisionObject3D", true, false).is_empty(), "presentation export adds no authority")
		if entry["file"] == "sweeper.glb":
			var players: Array[Node] = model.find_children("*", "AnimationPlayer", true, false)
			_check(players.size() == 1, "body carries its mechanical clips")
			if players.size() == 1:
				var player: AnimationPlayer = players[0] as AnimationPlayer
				for clip: String in ["walk", "raise", "fire", "recover", "hit", "death"]:
					_check(player.has_animation(clip), "import retains " + clip)
				player.play("walk")
				player.seek(0.0, true)
				var start: Transform3D = model.get_node("LeftLeg/Shin").transform
				player.seek(0.25, true)
				_check(not start.is_equal_approx(model.get_node("LeftLeg/Shin").transform), "imported walk moves the actual leg")
		if entry["file"] == "latch.glb":
			var skeletons: Array[Node] = model.find_children("*", "Skeleton3D", true, false)
			var players: Array[Node] = model.find_children("*", "AnimationPlayer", true, false)
			_check(skeletons.size() == 1 and players.size() == 1, "Latch library export retains one skin and gait player")
			if skeletons.size() == 1 and players.size() == 1:
				var skeleton: Skeleton3D = skeletons[0] as Skeleton3D
				var player: AnimationPlayer = players[0] as AnimationPlayer
				var leg: int = skeleton.find_bone("LeftLeg")
				_check(skeleton.get_bone_count() == 24 and leg >= 0 and player.has_animation("walk"), "Latch export keeps its actual weighted joints and walking clip")
				if leg >= 0 and player.has_animation("walk"):
					player.play("walk")
					player.seek(0.0, true)
					var start: Transform3D = skeleton.get_bone_pose(leg)
					player.seek(0.25, true)
					_check(not start.is_equal_approx(skeleton.get_bone_pose(leg)), "reimported Latch gait moves the actual leg bone")
			var weighted: int = 0
			for node: Node in model.find_children("*", "MeshInstance3D", true, false):
				weighted += 1 if (node as MeshInstance3D).skin != null else 0
			_check(weighted > 0, "reimported Latch surfaces retain their skin bindings")
		model.free()
	_fixture_bounds()
	for size: Vector3 in [Vector3(12, 6, 0.5), Vector3(0.5, 4, 18), Vector3(3, 3, 1.5)]:
		var mesh: ArrayMesh = ArchitectureMesh.wall(size)
		var bounds: AABB = mesh.get_aabb()
		_check(bounds.position.is_equal_approx(-size * 0.5) and bounds.size.is_equal_approx(size), "wall articulation retains exact authoritative volume bounds")
		var arrays: Array = mesh.surface_get_arrays(0)
		for normal: Vector3 in arrays[Mesh.ARRAY_NORMAL]:
			_check(normal.is_finite() and normal.length() > 0.99, "recess faces retain usable light normals")
	for size: Vector3 in [Vector3(4, 0.25, 6), Vector3(24, 0.5, 16), Vector3(80, 1, 80)]:
		var mesh: ArrayMesh = ArchitectureMesh.ceiling(size)
		var bounds: AABB = mesh.get_aabb()
		_check(bounds.position.is_equal_approx(-size * 0.5) and bounds.size.is_equal_approx(size), "ceiling coffers retain the slab's exact bounds")
		var arrays: Array = mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var recessed: int = 0
		for index: int in range(vertices.size()):
			_check(normals[index].is_finite() and normals[index].length() > 0.99, "coffer faces have usable lighting normals")
			if normals[index].y > 0.99:
				_check(is_equal_approx(vertices[index].y, size.y * 0.5), "upper walking surface stays exactly flat")
			if normals[index].y < -0.99 and vertices[index].y > -size.y * 0.5:
				recessed += 1
		_check(recessed > 0 and vertices.size() <= 8000, "ceiling has real inset panels and a bounded triangle count")
	_weapon_articulation()
	if DisplayServer.get_name() != "headless":
		await _normals_render()
	await process_frame
	if failures == 0:
		print("test_model_assets: PASS exported meshes, imported mechanical animation, fixture bounds, pump articulation and source receipts")
	quit(0 if failures == 0 else 1)

func _fixture_bounds() -> void:
	for size: Vector2 in [Vector2(0.125, 0.125), Vector2(1, 0.7), Vector2(16, 8)]:
		for kind: String in ["vent", "terminal", "lockers", "strip_light", "property_sign"]:
			var fixture: Node3D = Facility.new().build(kind, size)
			var pieces: Array[Node] = fixture.find_children("*", "MeshInstance3D", true, false)
			_check(pieces.size() == 1, "static fixtures share a merged mesh")
			var piece: MeshInstance3D = pieces[0] as MeshInstance3D
			_check(piece.mesh.get_surface_count() <= 3, "fixture draw surfaces stay bounded by finish")
			var bounds: AABB = piece.mesh.get_aabb()
			_check(bounds.position.x >= -size.x * 0.5 - 0.0001 and bounds.end.x <= size.x * 0.5 + 0.0001 \
				and bounds.position.y >= -size.y * 0.5 - 0.0001 and bounds.end.y <= size.y * 0.5 + 0.0001 \
				and bounds.end.z <= 0.0081, "fixture stays inside its registered face and shallow finish allowance")
			fixture.free()

func _weapon_articulation() -> void:
	var source: RefCounted = Shotgun.new()
	var gun: Node3D = source.build(true)
	var muzzle: Vector3 = gun.get_node("Muzzle").position
	source.pose(gun, 0.18)
	var rest: float = gun.get_node("Pump").position.z
	source.pose(gun, 0.31)
	_check(gun.get_node("Pump").position.z > rest + 0.10, "pump has a visible mechanical stroke")
	_check(gun.get_node("Pump/SupportHand") != null and gun.get_node("Muzzle").position == muzzle, "support glove travels with pump while muzzle remains on barrel")
	source.pose(gun, 0.5)
	_check(is_equal_approx(gun.get_node("Pump").position.z, rest), "gun returns to the same rest geometry")
	gun.free()

func _normals_render() -> void:
	for kind: String in ["sweeper", "clerk", "auditor"]:
		await _normal_body(kind)

func _normal_body(kind: String) -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(480, 360)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("6b746e")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_energy = 0.15
	viewport.add_child(environment)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-25, -55, 0)
	light.light_energy = 1.8
	viewport.add_child(light)
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.4
	viewport.add_child(camera)
	camera.position = Vector3(0, 0.9, 5)
	var body: Sprite3D = Sprite3D.new()
	body.position.y = 0.9
	viewport.add_child(body)
	var view: EnemyView = EnemyView.new()
	view.update({"campaign": {"kind": kind, "phase": "idle"}, "weapon": "Flechette"}, 1, body)
	body.position.y = 0.9
	body.frame = EnemyAnimation.pose_frame("idle", false, 0.0)
	var material: ShaderMaterial = body.material_override as ShaderMaterial
	_check(material.get_shader_parameter("normals_enabled") == true, "live " + kind + " presenter uses paired normal cells")
	_check(material.get_shader_parameter("sprite_normals") is Texture2D, "normal sampler has its imported texture")
	var first: Image = await _frame(viewport)
	material.set_shader_parameter("normals_enabled", false)
	var flat: Image = await _frame(viewport)
	material.set_shader_parameter("normals_enabled", true)
	light.rotation_degrees.y = 55
	var opposite: Image = await _frame(viewport)
	var shaped: int = 0
	var moving: int = 0
	for y: int in range(360):
		for x: int in range(480):
			shaped += 1 if absf(first.get_pixel(x, y).get_luminance() - flat.get_pixel(x, y).get_luminance()) > 0.025 else 0
			moving += 1 if absf(first.get_pixel(x, y).get_luminance() - opposite.get_pixel(x, y).get_luminance()) > 0.025 else 0
	_check(shaped > 100 and moving > 100, "actual normal pixels shape the body and respond to a moving light")
	var directory: String = ProjectSettings.globalize_path("res://../.agents/art-excellence-research/rendered")
	DirAccess.make_dir_recursive_absolute(directory)
	first.save_png(directory.path_join(kind + "-normal-lit.png"))
	flat.save_png(directory.path_join(kind + "-flat-lit.png"))
	opposite.save_png(directory.path_join(kind + "-opposite-light.png"))
	print("test_model_assets: ", kind, " rendered normal changes=", shaped, " moving light changes=", moving)
	viewport.free()

func _frame(viewport: SubViewport) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()
