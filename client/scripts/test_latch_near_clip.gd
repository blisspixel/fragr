extends SceneTree

var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(ok: bool, reason: String) -> void:
	if not ok:
		failures += 1
		push_error("test_latch_near_clip: " + reason)

func _run() -> void:
	var ward: LatchView = LatchView.new()
	root.add_child(ward)
	var live: LatchView = LatchView.new()
	root.add_child(live)
	var parts: Array[Node] = live.find_children("*", "MeshInstance3D", true, false)
	var transforms: Dictionary[String, Transform3D] = {}
	for node: Node in parts:
		var part: MeshInstance3D = node as MeshInstance3D
		transforms[str(live.get_path_to(part))] = part.transform
		_check(part.material_override is StandardMaterial3D, "the shared model starts with the ward's standard lit materials")
	live.set_near_camera_clip(true)
	_check(live.near_camera_clip and not ward.near_camera_clip and parts.size() <= 40, "only opted-in live companion changes presentation")
	for node: Node in parts:
		var part: MeshInstance3D = node as MeshInstance3D
		var path: String = str(live.get_path_to(part))
		var original: StandardMaterial3D = live._ward_materials[part]
		var clipped: ShaderMaterial = part.material_override as ShaderMaterial
		_check(clipped != null and clipped.shader == LatchView.NEAR_CLIP and part.transform == transforms[path],
			"near clipping never moves, rescales or adds geometry")
		_check(clipped.get_shader_parameter("chassis_color") == original.albedo_color
			and clipped.get_shader_parameter("chassis_metallic") == original.metallic
			and clipped.get_shader_parameter("chassis_roughness") == original.roughness
			and clipped.get_shader_parameter("camera_clearance") == 0.7,
			"live material retains original color and surface response with bounded clearance")
		_check((ward.get_node(path) as MeshInstance3D).material_override is StandardMaterial3D,
			"each ward part remains unchanged")
	live.set_near_camera_clip(true)
	_check(live._ward_materials.size() == parts.size(), "repeated opt-in retains a bounded material set")
	live.set_near_camera_clip(false)
	for node: Node in parts:
		var part: MeshInstance3D = node as MeshInstance3D
		_check(part.material_override == live._ward_materials[part], "disabling clipping restores exact original resources")
	ward.pose_release(1.0)
	_check(ward.get_node("RightArm/Hand").rotation.x < -0.3 and ward.get_node("RightArm/Tack").visible == false,
		"ward voluntary hand gesture and hidden weapon remain intact")
	var pawn: Node3D = load("res://scenes/player.tscn").instantiate()
	root.add_child(pawn)
	pawn.set_process(false)
	pawn.set_player_data("ally", "Latch")
	pawn.update_state({"id": "ally", "name": "Latch", "x": 2.0, "y": 1.5, "z": 3.0, "yaw": 0.0,
		"hp": 100, "weapon": "Tack", "just_fired": false,
		"campaign": {"side": "companion", "kind": "latch", "phase": "following", "phase_started": 10}}, 10)
	_check(pawn.latch_view.near_camera_clip and pawn.target_position == Vector3(2, 1.5, 3)
		and pawn.latch_view.position == Vector3(0, -1.5, 0) and pawn.latch_view.scale == Vector3.ONE,
		"actual live-pawn connector opts in without changing authoritative target or registered figure")
	pawn.latch_view.shot()
	_check(pawn.latch_view.get_node("RightArm/Tack/Flash").visible
		and (pawn.latch_view.get_node("RightArm/Tack/Flash") as MeshInstance3D).material_override is ShaderMaterial,
		"confirmed companion fire keeps its flash through the clipped presentation")
	pawn.free()
	if DisplayServer.get_name() != "headless":
		await _rendered(live)
	live.free()
	ward.free()
	if failures == 0:
		print("test_latch_near_clip: PASS bounded opt-in material, immutable geometry, ward gesture and exact restoration")
	quit(0 if failures == 0 else 1)

func _rendered(live: LatchView) -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(128, 128)
	viewport.world_3d = World3D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	live.reparent(viewport)
	live.transform = Transform3D.IDENTITY
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("381421")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	world.environment.ambient_light_energy = 1.0
	viewport.add_child(world)
	var camera: Camera3D = Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(0, 1.22, 0.45)
	camera.look_at(Vector3(0, 1.22, 0))
	camera.current = true
	live.visible = false
	var empty: Image = await _frame(viewport)
	var clear: Color = empty.get_pixel(64, 64)
	live.visible = true
	live.set_near_camera_clip(false)
	var original: Image = await _frame(viewport)
	_check(_color_distance(original.get_pixel(64, 64), clear) > 0.1, "original close torso actually occupies the aiming pixel")
	live.set_near_camera_clip(true)
	var clipped: Image = await _frame(viewport)
	_check(_color_distance(clipped.get_pixel(64, 64), clear) < 0.03, "actual shader removes the intrusive near-camera aiming polygon")
	camera.position.z = 2.5
	var distant: Image = await _frame(viewport)
	_check(_color_distance(distant.get_pixel(64, 64), clear) > 0.1, "actual shader retains the ordinary distant opaque companion")
	var directory: String = ProjectSettings.globalize_path("res://../.agents/m04-client-buildout-20260930")
	DirAccess.make_dir_recursive_absolute(directory)
	original.save_png(directory.path_join("latch-near-original.png"))
	clipped.save_png(directory.path_join("latch-near-clipped.png"))
	distant.save_png(directory.path_join("latch-distant-clipped.png"))
	camera.position = Vector3(0, 1.55, 0.45)
	camera.look_at(Vector3(0, 2.45, -1))
	var upward: Image = await _frame(viewport)
	var upper_pixels: int = 0
	for y: int in range(64):
		for x: int in range(128):
			if _color_distance(upward.get_pixel(x, y), clear) > 0.03:
				upper_pixels += 1
	_check(upper_pixels == 0, "upward first-person view retains no close head or shoulder fragments in the sky")
	upward.save_png(directory.path_join("latch-upward-clipped.png"))
	live.reparent(root)
	viewport.free()
	print("test_latch_near_clip: rendered PASS actual close/distant pixels")

func _frame(viewport: SubViewport) -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

static func _color_distance(first: Color, second: Color) -> float:
	return Vector3(first.r, first.g, first.b).distance_to(Vector3(second.r, second.g, second.b))
