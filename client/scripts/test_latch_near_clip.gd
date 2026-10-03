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
			and clipped.get_shader_parameter("finish_enabled") == (original.albedo_texture != null)
			and clipped.get_shader_parameter("chassis_metallic") == original.metallic
			and clipped.get_shader_parameter("chassis_roughness") == original.roughness
			and clipped.get_shader_parameter("near_hide_distance") == 1.1
			and clipped.get_shader_parameter("near_full_distance") == 1.35
			and clipped.get_shader_parameter("chassis_origin") == live.global_position,
			"live material retains original surface response and one bounded world-space near transition")
		if original.albedo_texture != null:
			_check(clipped.get_shader_parameter("chassis_finish") == original.albedo_texture, "near presentation preserves the actual workshop finish")
		_check((ward.get_node(path) as MeshInstance3D).material_override is StandardMaterial3D,
			"each ward part remains unchanged")
	live.set_near_camera_clip(true)
	_check(live._ward_materials.size() == parts.size(), "repeated opt-in retains a bounded material set")
	live.position = Vector3(3, 0.25, -4)
	live._process(0.0)
	for node: Node in parts:
		_check(((node as MeshInstance3D).material_override as ShaderMaterial).get_shader_parameter("chassis_origin") == live.global_position,
			"moving the actual figure updates every existing part to the same world anchor")
	live.set_near_camera_clip(false)
	_check(not live.is_processing(), "ward restoration stops live origin updates")
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
		print("test_latch_near_clip: PASS coherent near visibility, immutable geometry, ward gesture and exact restoration")
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
	await _transition_sweep(viewport, camera, live, clear)
	await _shadow_retained(viewport, camera, live, world)
	live.reparent(root)
	viewport.free()
	if failures == 0:
		print("test_latch_near_clip: rendered PASS actual close/offset/transition/distant pixels and retained shadow")

func _transition_sweep(viewport: SubViewport, camera: Camera3D, live: LatchView, background: Color) -> void:
	viewport.size = Vector2i(320, 180)
	var original_board: Image = Image.create(1280, 720, false, Image.FORMAT_RGBA8)
	var corrected_board: Image = Image.create(1280, 720, false, Image.FORMAT_RGBA8)
	var samples: Array[Dictionary] = []
	var index: int = 0
	for offset: float in [0.0, 0.25]:
		var previous_coverage: float = 0.0
		for distance: float in [0.6, 0.75, 0.9, 1.05, 1.15, 1.25, 1.4, 2.5]:
			camera.position = Vector3(offset, MoveStep.EYE_HEIGHT, distance)
			# Frame the shorter civilian chassis while retaining an upward offset view.
			camera.rotation = Vector3(0.25 if offset == 0.0 else 0.4, 0.0, 0.0)
			live.set_near_camera_clip(false)
			var original: Image = await _frame(viewport)
			live.set_near_camera_clip(true)
			var corrected: Image = await _frame(viewport)
			var original_pixels: int = 0
			var corrected_pixels: int = 0
			var outside: int = 0
			var coverage_cells: Dictionary[Vector2i, bool] = {}
			var incoherent: int = 0
			for y: int in range(180):
				for x: int in range(320):
					var before: bool = _color_distance(original.get_pixel(x, y), background) > 0.03
					var after: bool = _color_distance(corrected.get_pixel(x, y), background) > 0.03
					original_pixels += int(before)
					corrected_pixels += int(after)
					outside += int(after and not before)
					if before:
						var cell: Vector2i = Vector2i(x % 4, y % 4)
						if coverage_cells.has(cell):
							incoherent += int(coverage_cells[cell] != after)
						else:
							coverage_cells[cell] = after
			_check(original_pixels > 1000, "actual unmodified rig occupies the near-transition raster")
			_check(outside == 0, "coherent coverage never projects geometry outside the original complete silhouette")
			_check(incoherent == 0, "every visible chassis part uses the same coverage instead of retaining isolated far faces")
			var coverage: float = float(corrected_pixels) / maxf(1.0, float(original_pixels))
			_check(coverage >= previous_coverage, "actual figure coverage increases monotonically as the camera leaves the close space")
			previous_coverage = coverage
			if distance <= 0.9:
				_check(corrected_pixels == 0, "actual intermediate close head and arms leave no disconnected facets or aiming occlusion")
			elif distance >= 1.4:
				_check(corrected_pixels == original_pixels, "ordinary distant full rig remains completely opaque at both camera offsets")
			elif distance == 1.15:
				_check(corrected_pixels > 0 and corrected_pixels < original_pixels, "short near transition retains distributed figure coverage")
			var slot: Vector2i = Vector2i((index % 4) * 320, (index / 4) * 180)
			original_board.blit_rect(original, Rect2i(Vector2i.ZERO, Vector2i(320, 180)), slot)
			corrected_board.blit_rect(corrected, Rect2i(Vector2i.ZERO, Vector2i(320, 180)), slot)
			samples.append({"offset": offset, "pitch": camera.rotation.x, "distance": distance,
				"original_pixels": original_pixels, "corrected_pixels": corrected_pixels, "outside": outside})
			index += 1
	var directory: String = ProjectSettings.globalize_path("res://../.agents/m06-buildout-20261001/latch-near-corrected")
	DirAccess.make_dir_recursive_absolute(directory)
	_check(original_board.save_png(directory.path_join("original-motion.png")) == OK
		and corrected_board.save_png(directory.path_join("corrected-motion.png")) == OK, "actual original and corrected motion boards save")
	var receipt: FileAccess = FileAccess.open(directory.path_join("samples.json"), FileAccess.WRITE)
	_check(receipt != null, "actual transition sample receipt opens")
	if receipt != null:
		receipt.store_string(JSON.stringify(samples, "  "))
		receipt.close()
	# Actor movement updates the shared anchor; render-camera movement needs no CPU eye update.
	live.position = Vector3(4, 0.5, -3)
	live._process(0.0)
	camera.position = live.position + Vector3(0.25, MoveStep.EYE_HEIGHT, 0.75)
	camera.rotation = Vector3(0.45, 0, 0)
	var moved: Image = await _frame(viewport)
	var remaining: int = 0
	for y: int in range(180):
		for x: int in range(320):
			remaining += int(_color_distance(moved.get_pixel(x, y), background) > 0.03)
	_check(remaining == 0, "moved actual chassis retains coherent clearance with translated height and render eye")
	live.position = Vector3.ZERO
	live._process(0.0)

func _shadow_retained(viewport: SubViewport, camera: Camera3D, live: LatchView, world: WorldEnvironment) -> void:
	world.environment.ambient_light_energy = 0.12
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 25, 0)
	light.light_energy = 1.0
	light.shadow_enabled = true
	viewport.add_child(light)
	var floor: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(8, 8)
	floor.mesh = plane
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	material.roughness = 1.0
	floor.material_override = material
	viewport.add_child(floor)
	camera.position = Vector3(0, 1.22, 0.45)
	camera.look_at(Vector3(0, 0.0, -2))
	live.visible = false
	var empty: Image = await _frame(viewport)
	live.visible = true
	var shadowed: Image = await _frame(viewport)
	var darker: int = 0
	for y: int in range(180):
		for x: int in range(320):
			if empty.get_pixel(x, y).get_luminance() - shadowed.get_pixel(x, y).get_luminance() > 0.03:
				darker += 1
	_check(darker > 200, "actual shadow pass retains the close figure's opaque world silhouette")
	var directory: String = ProjectSettings.globalize_path("res://../.agents/m06-buildout-20261001/latch-near-corrected")
	_check(empty.save_png(directory.path_join("shadow-floor-empty.png")) == OK
		and shadowed.save_png(directory.path_join("shadow-floor-retained.png")) == OK, "actual preserved-shadow evidence saves")

func _frame(viewport: SubViewport) -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	return image

static func _color_distance(first: Color, second: Color) -> float:
	return Vector3(first.r, first.g, first.b).distance_to(Vector3(second.r, second.g, second.b))
