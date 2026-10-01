extends SceneTree

var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_arena_water: " + message)

## Actual authored bounds and registered decorations, projected as a wire fixture.
func _map() -> Dictionary:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../server/maps/m04_notice_to_vacate.json"))
	var info: Dictionary = {"map_id": source["map_id"], "map_name": source["name"], "half_extent": source["half_extent"],
		"geometry_version": 2, "solids": [], "m04": {"clinic_open": false},
		"presentation": {"ground": source["ground"], "solids": [], "decorations": []}}
	var indices: Dictionary[String, int] = {}
	for solid: Dictionary in source["solids"]:
		indices[solid["id"]] = info["solids"].size()
		info["solids"].append({"min_x": solid["min"][0], "max_x": solid["max"][0], "bottom": solid["min"][1],
			"top": solid["max"][1], "min_z": solid["min"][2], "max_z": solid["max"][2]})
		info["presentation"]["solids"].append(solid["surface"])
	for decoration: Dictionary in source["decorations"]:
		var copy: Dictionary = decoration.duplicate(true)
		copy["solid"] = indices[decoration["solid"]]
		info["presentation"]["decorations"].append(copy)
	return info

func _run() -> void:
	var info: Dictionary = _map()
	var original: Dictionary = info.duplicate(true)
	_check(MapGeometry.validation_error(info).is_empty(), "actual Low Water solid fixture passes shared geometry boundary")
	var cover: ArenaCover = ArenaCover.new()
	root.add_child(cover)
	cover.apply_map_info(info)
	var water: ArenaWater = cover.get_node_or_null("ShallowWater") as ArenaWater
	_check(water != null and water.patches.size() == 3, "live ArenaCover integrates all three unobstructed registered venue puddles")
	if water == null:
		cover.free()
		quit(1)
		return
	_check(water.get_child_count() == 33 and water.find_children("*", "CollisionObject3D", true, false).is_empty(), "three bounded water/drain/paper groups add no collision")
	for patch: MeshInstance3D in water.patches:
		_check(patch.layers == ArenaSky.WORLD_LAYERS and is_equal_approx(patch.position.y, ArenaWater.HEIGHT), "flat shallow water stays on world layers at floor height")
		_check(patch.material_override is ShaderMaterial and patch.mesh is PlaneMesh, "live water uses the original opaque shader and fixed plane")
	water.set_ripple_time(0.25)
	_check(is_equal_approx(float(water._materials[0].get_shader_parameter("ripple_time")), 0.25), "registered materials receive bounded deterministic animation")
	water.set_ripple_time(NAN)
	_check(is_equal_approx(water._clock, 0.25), "nonfinite time cannot contaminate materials")
	cover.apply_map_info(info)
	_check(cover.get_node("ShallowWater") == water and info == original, "duplicate map leaves existing water and authority dictionary unchanged")
	var opened: Dictionary = info.duplicate(true)
	opened["m04"]["clinic_open"] = true
	for solid: Dictionary in opened["solids"]:
		if float(solid["min_x"]) == -22.5 and float(solid["min_z"]) == 0.0:
			solid["bottom"] += 3.2
			solid["top"] += 3.2
	cover.apply_map_info(opened)
	water = cover.get_node("ShallowWater") as ArenaWater
	_check(water.patches.size() == 3 and cover.find_children("ShallowWater", "ArenaWater", false, false).size() == 1, "prepared clinic handoff replaces one water group without leaks")
	var blocked: Dictionary = info.duplicate(true)
	blocked["solids"].append({"min_x": 4, "max_x": 6, "min_z": -15, "max_z": -13})
	blocked["presentation"]["solids"].append("concrete")
	water.build(blocked)
	_check(water.patches.size() == 2, "a current server solid refuses its overlapping cosmetic patch")
	var unknown: Dictionary = info.duplicate(true)
	unknown["map_id"] = 1003
	water.build(unknown)
	_check(water.patches.is_empty() and water.get_child_count() == 0, "other venues clear water and ground dressing")
	unknown = info.duplicate(true)
	unknown["presentation"]["decorations"].clear()
	water.build(unknown)
	_check(water.patches.is_empty(), "map ID alone cannot invent an unregistered puddle placement")
	_check(not water.add_patch("bad", Vector2.INF, Vector2.ONE, 40, []) \
		and not water.add_patch("bad", Vector2.ZERO, Vector2(20, 20), 40, []) \
		and not water.add_patch("bad", Vector2(39, 0), Vector2(2, 2), 40, []) \
		and not water.add_patch("bad", Vector2.ZERO, Vector2.ONE, 40, [null]), "reusable surface refuses invalid finite bounds and malformed solids")
	water.build(info)
	_check(not water.add_patch("Duplicate", Vector2(5, -14), Vector2.ONE, 40, []), "reusable additions cannot stack overlapping water surfaces")
	for index: int in range(10):
		water.add_patch("Extra%d" % index, Vector2(-5 - index * 3, -28), Vector2.ONE, 40, info["solids"])
	_check(water.patches.size() == ArenaWater.MAX_PATCHES and water.get_child_count() == 44, "reusable additions retain a fixed mesh budget")
	cover.free()
	if DisplayServer.get_name() != "headless":
		await _rendered(info)
	await process_frame
	if failures == 0:
		print("test_arena_water: PASS actual venue geometry, integrated animated surfaces, drain dressing, bounded lifecycle and collision isolation")
	quit(0 if failures == 0 else 1)

func _rendered(info: Dictionary) -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(480, 320)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("bdd0c0")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.8
	viewport.add_child(environment)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-65, -25, 0)
	light.light_energy = 0.65
	viewport.add_child(light)
	var cover: ArenaCover = ArenaCover.new()
	viewport.add_child(cover)
	cover.apply_map_info(info)
	var water: ArenaWater = cover.get_node("ShallowWater") as ArenaWater
	water.set_process(false)
	var camera: Camera3D = Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(5, 3.5, -9.8)
	camera.look_at(Vector3(5, 0, -14))
	camera.current = true
	water.set_ripple_time(0.0)
	var first: Image = await _frame(viewport)
	water.set_ripple_time(2.0)
	var second: Image = await _frame(viewport)
	var changed: int = 0
	for y: int in range(320):
		for x: int in range(480):
			if _difference(first.get_pixel(x, y), second.get_pixel(x, y)) > 0.04:
				changed += 1
	_check(changed > 100, "actual integrated water visibly changes pixels across distinct ripple times")
	var directory: String = ProjectSettings.globalize_path("res://../.agents/environment-water-20260930")
	DirAccess.make_dir_recursive_absolute(directory)
	first.save_png(directory.path_join("water-street-00.png"))
	second.save_png(directory.path_join("water-street-02.png"))
	var strip: Image = Image.create(480 * 4, 320, false, first.get_format())
	for index: int in range(4):
		water.set_ripple_time(float(index) * 0.75)
		var frame: Image = await _frame(viewport)
		strip.blit_rect(frame, Rect2i(0, 0, 480, 320), Vector2i(index * 480, 0))
	strip.save_png(directory.path_join("water-motion-strip.png"))
	# A real opaque registered scene surface must still hide the water below it.
	var blocker: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(4, 0.3, 2.8)
	blocker.mesh = box
	blocker.position = Vector3(5, 0.25, -14)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("b05b42")
	blocker.material_override = material
	viewport.add_child(blocker)
	var hidden: Image = await _frame(viewport)
	_check(_difference(hidden.get_pixel(240, 160), Color("b05b42")) < 0.08, "ordinary opaque geometry depth-occludes the water")
	hidden.save_png(directory.path_join("water-depth-occluded.png"))
	viewport.free()
	print("test_arena_water: rendered PASS actual animated pixels, shore/drain scene and depth occlusion; changed=", changed)

func _frame(viewport: SubViewport) -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

static func _difference(first: Color, second: Color) -> float:
	return Vector3(first.r, first.g, first.b).distance_to(Vector3(second.r, second.g, second.b))
