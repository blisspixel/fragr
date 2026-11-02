extends SceneTree

var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("test_mars_venues: " + message)

func _run() -> void:
	for pair: Array in [["Launch Authority (development)", "launch_works"], ["Terms of Cooperation (development)", "mars_habitat"], ["The Weight of Permission (development)", "mars_foundry"]]:
		var venue: String = pair[1]
		_check(ArenaCover.venue_for({"map_name": pair[0], "map_id": 1014}) == venue,
			"display name selects its explicit development venue")
		for surface: String in ["concrete", "enamel", "service_steel", "records_tile", "lift_panel"]:
			if venue == "mars_foundry" and surface == "records_tile":
				var process: StandardMaterial3D = ArenaMaterials.authored(surface, venue) as StandardMaterial3D
				_check(process != null and process.emission_enabled and process.albedo_texture != null and process.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST,
					"shielded foundry process uses a steady warm offline material with nearest filtering")
				continue
			var material: ShaderMaterial = ArenaMaterials.authored(surface, venue) as ShaderMaterial
			_check(material != null and material.get_shader_parameter("tile_enabled") == true,
				"registered Mars surface reuses an offline tile: " + surface)
			_check(material.get_shader_parameter("tile_wall") != null and material.get_shader_parameter("tile_floor") != null,
				"both face directions load their registered tile")
		_check(EnvironmentTextures.path_for("inspection_glass", venue).is_empty(), "opaque tiles never replace glass")
		if venue == "launch_works":
			_check((ArenaMaterials.authored("concrete", venue) as ShaderMaterial).get_shader_parameter("markings_enabled") == false,
				"launch dust terrain has no institutional slab markings")
		else:
			_check((ArenaMaterials.authored("concrete", venue) as ShaderMaterial).get_shader_parameter("markings_enabled") != false,
				"constructed Mars working floors retain slab markings")
		var backdrop: ArenaBackdrop = ArenaBackdrop.new()
		root.add_child(backdrop)
		backdrop.build(1014, 70.0, venue)
		for child: Node in backdrop.get_children():
			if not child is MeshInstance3D:
				continue
			var mesh: MeshInstance3D = child as MeshInstance3D
			var box: AABB = mesh.transform * mesh.mesh.get_aabb()
			_check(box.end.x < -70.0 or box.position.x > 70.0 or box.end.z < -70.0 or box.position.z > 70.0,
				"every backdrop mesh stays strictly beyond the authoritative square")
		backdrop.queue_free()
	_check(ArenaCover.venue_for({"map_name": "Custody Device Range", "map_id": 1014}).is_empty(),
		"shared historical map ID does not infer Mars or a vehicle venue")
	_check(EnvironmentTextures.path_for("concrete", "mars").is_empty(), "unregistered generic Mars keeps its fallback")
	for surface: String in ["concrete", "records_tile"]:
		_check((ArenaMaterials.authored(surface, "moon_town") as ShaderMaterial).get_shader_parameter("warning_color") == (ArenaMaterials.authored(surface) as ShaderMaterial).get_shader_parameter("warning_color"),
			"Mars quiet paint does not change the existing Moon town surface: " + surface)
	await process_frame
	if failures == 0:
		print("test_mars_venues: PASS explicit development names, offline tiles, glass isolation and outside-bounds backdrop")
	quit(0 if failures == 0 else 1)
