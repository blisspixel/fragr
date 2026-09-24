extends SceneTree

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_arena_sky: " + message)

func _run() -> void:
	var recall: ArenaSky.Preset = ArenaSky.preset_for("Recall Notice: intake prototype")
	var scrap: ArenaSky.Preset = ArenaSky.preset_for("Arena Duel")
	var yard: ArenaSky.Preset = ArenaSky.preset_for("Compliance Yard")
	var ward: ArenaSky.Preset = ArenaSky.preset_for("Persons Unknown: ward graybox")
	_check(ward.ambient_color == recall.ambient_color and ward.interior, "the M02 ward fell through to an outdoor fill")
	_check(recall.interior and not scrap.interior and not yard.interior, "venue interiors are not matched explicitly")
	_check(recall.ambient_color != scrap.ambient_color, "Recall Notice still uses the scrapyard fill")
	_check(yard.ambient_color != scrap.ambient_color, "Compliance Yard lost its own sky")
	# Interiors are lit by their fixtures now. The ambient floor is lower than
	# the old flat 1.05 but never low enough to put a wall at arm's length in
	# pure black, and the fixtures must be the brighter light in the room.
	_check(recall.ambient_energy >= 0.3 and recall.ambient_energy < 1.0, "interior ambient floor left its readable band")
	_check(recall.practical_energy > scrap.practical_energy * 2.0 and recall.practical_range > scrap.practical_range, "interior fixtures do not dominate the ambient floor")
	_check(recall.accent_energy > 0.0 and scrap.accent_energy == 0.0, "Union seals lost their red lamp, or it leaked to the arena")
	_check(recall.view_fill_energy > 0.0 and recall.view_fill_range >= 30.0, "interior enemies lost their readability fill at aisle range")

	var environment: Environment = ArenaSky.build_environment("Recall Notice")
	_check(environment.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR and is_equal_approx(environment.ambient_light_energy, recall.ambient_energy), "interior ambient is not the authored flat floor")
	_check(environment.fog_enabled and is_equal_approx(environment.fog_density, recall.fog_density) and not environment.glow_enabled, "fog or glow defaults changed outside quality")

	var layout: Node3D = Node3D.new()
	root.add_child(layout)
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.name = "KeyLight"
	layout.add_child(key)
	var ember: OmniLight3D = OmniLight3D.new()
	ember.name = "EmberPit"
	layout.add_child(ember)
	ArenaSky.apply_scene_lights(layout, "Recall Notice")
	_check(not ember.visible and is_equal_approx(key.light_energy, recall.key_energy), "interior kept the outdoor ember props or sun")
	ArenaSky.apply_scene_lights(layout, "Arena Duel")
	_check(ember.visible and is_equal_approx(key.light_energy, scrap.key_energy), "arena lost its ember props or sun")

	var camera: Camera3D = Camera3D.new()
	root.add_child(camera)
	ArenaSky.apply_view_fill(camera, "Recall Notice")
	var fill: OmniLight3D = camera.get_node_or_null(ArenaSky.VIEW_FILL) as OmniLight3D
	_check(fill != null and fill.light_cull_mask == ArenaSky.ACTOR_LAYERS and not fill.shadow_enabled, "view fill must light actors only, without a shadow map")
	ArenaSky.apply_view_fill(camera, "Recall Notice")
	_check(camera.get_child_count() == 1, "reapplying the venue stacked a second view fill")

	var world: Node3D = Node3D.new()
	var wall: MeshInstance3D = MeshInstance3D.new()
	world.add_child(wall)
	ArenaSky.mark_world(world)
	_check(wall.layers == ArenaSky.WORLD_LAYERS and (wall.layers & ArenaSky.ACTOR_LAYERS) == 0, "world geometry still receives the actor fill")
	world.free()

	var info: Dictionary = {"solids": [{"min_x": -1.0, "max_x": 1.0, "min_z": -1.0, "max_z": 1.0, "bottom": 0.0, "top": 3.0}]}
	var details: Array = [
		{"solid": 0, "face": "down", "kind": "strip_light", "center": [0.0, 0.0], "size": [1.0, 0.5]},
		{"solid": 0, "face": "north", "kind": "union_seal", "center": [0.0, 0.0], "size": [1.0, 1.0]},
	]
	var parent: Node3D = Node3D.new()
	root.add_child(parent)
	ArenaDecoration.build(parent, info["solids"], details, recall)
	var practical: OmniLight3D = parent.get_node("Detail_0_strip_light/Practical") as OmniLight3D
	_check(is_equal_approx(practical.light_energy, recall.practical_energy) and practical.is_in_group(ArenaSky.PRACTICAL_GROUP), "practical does not follow the venue or quality group")
	var seal: OmniLight3D = parent.get_node_or_null("Detail_1_union_seal/SealLamp") as OmniLight3D
	_check(seal != null and seal.light_color.r > seal.light_color.g * 3.0 and not seal.shadow_enabled, "Union seal lamp is missing or not red")

	camera.free()
	layout.free()
	parent.free()
	await process_frame
	if _failures == 0:
		print("test_arena_sky: PASS venue presets, interior fixtures, red seal lamps, actor-only view fill and world layers")
	quit(0 if _failures == 0 else 1)
