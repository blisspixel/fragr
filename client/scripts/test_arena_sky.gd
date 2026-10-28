extends SceneTree

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_arena_sky: " + message)

func _run() -> void:
	var recall: ArenaSky.Preset = ArenaSky.preset_for("Recall Notice")
	var scrap: ArenaSky.Preset = ArenaSky.preset_for("Arena Duel")
	var yard: ArenaSky.Preset = ArenaSky.preset_for("Compliance Yard")
	var ward: ArenaSky.Preset = ArenaSky.preset_for("Persons Unknown")
	var freight: ArenaSky.Preset = ArenaSky.preset_for("Scheduled Service: recall freight yard")
	var town: ArenaSky.Preset = ArenaSky.preset_for("Notice to Vacate: Low Water market")
	var launch: ArenaSky.Preset = ArenaSky.preset_for("Launch Authority (development)")
	var habitat: ArenaSky.Preset = ArenaSky.preset_for("Terms of Cooperation (development)")
	var foundry: ArenaSky.Preset = ArenaSky.preset_for("The Weight of Permission (development)")
	_check(foundry.interior and foundry.key_energy == 0.0 and not foundry.outdoor_embers and foundry.practical_color.g > foundry.practical_color.r,
		"roofed foundry requires explicit neutral work lighting without an exterior sun")
	_check(not launch.interior and launch.key_color.r > launch.key_color.b and launch.sky_top != scrap.sky_top,
		"launch works require an explicitly registered dust-lit Mars exterior")
	_check(habitat.sky_top != launch.sky_top and habitat.practical_energy > launch.practical_energy,
		"habitat courts need their distinct neutral work-light plan")
	_check(ArenaSky.preset_for("Launch Authority test fixture").sky_top == scrap.sky_top,
		"a similar unknown display name must keep the established fallback")
	_check(not town.interior and town.sky_top != freight.sky_top and town.key_color.r > town.key_color.b,
		"Low Water needs its own warm afternoon sky and light")
	_check(not freight.interior and freight.sky_top != scrap.sky_top and freight.fog_density < scrap.fog_density,
		"M03 lost its explicit open daylight sky")
	_check(ward.interior and ward.ambient_color != scrap.ambient_color, "the M02 ward fell through to an outdoor fill")
	# M01 keeps a readable floor (energy times the tint's luminance) while its
	# strips and warm lamps carry the pools; enemies keep the actor view fill.
	var intake_floor: float = recall.ambient_energy * recall.ambient_color.get_luminance()
	var facility: ArenaSky.Preset = ArenaSky.facility()
	_check(recall.practical_energy > facility.practical_energy and intake_floor >= 0.3 and intake_floor < facility.ambient_energy * facility.ambient_color.get_luminance(),
		"the M01 intake lost its fixture-led light plan or its readable floor")
	# M02's correction rooms: bounded fixture pools over a readable floor a step
	# below the generic facility, and enemies keep the actor view fill.
	var ward_floor: float = ward.ambient_energy * ward.ambient_color.get_luminance()
	_check(ward_floor >= 0.3 and ward_floor < facility.ambient_energy * facility.ambient_color.get_luminance() and ward.practical_energy > ward.ambient_energy * 4.0,
		"the M02 ward lost its fixture-led light plan or its readable floor")
	_check(ward.view_fill_energy > 0.0 and ward.view_fill_range >= 30.0 and ward.accent_energy > 0.0, "M02 guards lost their readability fill or seal lamps")
	_check(recall.interior and not scrap.interior and not yard.interior, "venue interiors are not matched explicitly")
	_check(recall.ambient_color != scrap.ambient_color, "Recall Notice still uses the scrapyard fill")
	_check(yard.ambient_color != scrap.ambient_color, "Compliance Yard lost its own sky")
	# Interiors read like Doom and Dusk rooms: a clearly lit base with brighter
	# fixture pools on top, never a dark baseline.
	_check(recall.ambient_energy >= 0.75, "interior ambient floor dropped below the readable base")
	_check(scrap.ambient_energy >= 0.65 and yard.ambient_energy >= 0.65, "arena ambient floor dropped below the readable base")
	_check(recall.practical_energy > scrap.practical_energy * 2.0 and recall.practical_range > scrap.practical_range, "interior fixtures do not dominate the ambient floor")
	_check(recall.accent_energy > 0.0 and scrap.accent_energy == 0.0, "Union seals lost their red lamp, or it leaked to the arena")
	_check(recall.view_fill_energy > 0.0 and recall.view_fill_range >= 30.0, "interior enemies lost their readability fill at aisle range")

	var environment: Environment = ArenaSky.build_environment("Recall Notice")
	_check(environment.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR and is_equal_approx(environment.ambient_light_energy, recall.ambient_energy), "interior ambient is not the authored flat floor")
	_check(environment.fog_enabled and is_equal_approx(environment.fog_density, recall.fog_density) and not environment.glow_enabled, "fog or glow defaults changed outside quality")

	# Small bloom: only the tight levels carry glow, and the threshold stays
	# above a lit wall so a lamp head glows and the room around it does not.
	for level: int in range(3, 7):
		_check(is_zero_approx(environment.get_glow_level(level)), "a wide glow level would wash a wall: %d" % (level + 1))
	_check(environment.get_glow_level(0) > 0.0 and environment.glow_hdr_threshold >= 0.8 and environment.glow_bloom == 0.0, "glow lost its small-bloom shape")
	# The Pit's haze sits under the first deck and never reaches a fighter's chest.
	var lot: Environment = ArenaSky.build_environment("Larak Lot")
	_check(lot.fog_height_density > 0.0 and lot.fog_height < 1.5, "Larak Lot lost its Pit haze, or it climbed onto the decks")
	_check(1.0 - exp(-lot.fog_height_density * lot.fog_height) < 0.25, "the Pit haze is too thick on the Pit floor")
	_check(is_zero_approx(environment.fog_height_density), "height haze leaked into an interior")

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
	var larak: ArenaSky.Preset = ArenaSky.preset_for("Larak Lot")
	_check(not larak.interior and not larak.outdoor_embers and not larak.key_in_sky and larak.sky_top != scrap.sky_top \
		and larak.view_fill_energy > 0.0 and larak.practical_color.r > larak.practical_color.b \
		and larak.accent_energy == 0.0,
		"Larak Lot needs its own night sky, sodium practicals and actor fill without a sun disc or a red seal lamp")
	var authored: Vector3 = key.rotation_degrees
	ArenaSky.apply_scene_lights(layout, "Larak Lot")
	_check(not ember.visible and key.sky_mode == DirectionalLight3D.SKY_MODE_LIGHT_ONLY \
		and key.rotation_degrees.is_equal_approx(larak.key_rotation_degrees), "Larak Lot kept the scrapyard sun or embers")
	ArenaSky.apply_scene_lights(layout, "Arena Duel")
	_check(key.sky_mode == DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY and key.rotation_degrees.is_equal_approx(authored),
		"leaving Larak Lot did not restore the authored key light")
	ArenaSky.apply_scene_lights(layout, "Launch Authority (development)")
	_check(not ember.visible and is_equal_approx(key.light_energy, launch.key_energy), "Mars retained unmotivated scrapyard ember lamps")

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
