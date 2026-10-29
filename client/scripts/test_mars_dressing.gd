extends SceneTree

var failures: int = 0
func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")
func _expect(condition: bool, why: String) -> void:
	if not condition:
		failures += 1
		push_error("test_mars_dressing: " + why)

func _run() -> void:
	for mission: int in [12, 13]:
		var vectors: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://golden/m13_fact_vectors.json"))
		var info: Dictionary = habitat_fixture() if mission == 12 else vectors["map_info"]
		var original: Dictionary = info.duplicate(true)
		var dressing: M06Dressing = M12Dressing.new() if mission == 12 else M13Dressing.new()
		root.add_child(dressing)
		dressing.configure_map(info)
		_expect(dressing.active(), "canonical M%d gets dressing" % mission)
		var count: int = dressing.get_child_count()
		_expect(count >= 7, "every major M%d area has its own detail" % mission)
		var first: Node = dressing.get_child(0)
		dressing.configure_map(info.duplicate(true))
		_expect(dressing.get_child_count() == count and dressing.get_child(0) == first, "identical resend keeps one set of rooms")
		_expect(info == original, "dressing does not mutate the map or mission facts")
		_expect(dressing.find_children("*", "CollisionObject3D", true, false).is_empty(), "no client collision is introduced")
		_expect(dressing.find_children("*", "Label3D", true, false).is_empty(), "no additional signs or outcomes")
		for node: Node in dressing.find_children("*", "Light3D", true, false):
			var light: Light3D = node as Light3D
			_expect(not light.shadow_enabled, "local fixtures add no shadow maps")
			_expect(light.light_color.r >= light.light_color.b and light.light_color.g >= 0.6, "work light is neutral or amber, never red or cyan")
		for node: Node in dressing.find_children("*", "VisualInstance3D", true, false):
			_expect(((node as VisualInstance3D).layers & ArenaSky.ACTOR_LAYERS) == 0, "world detail never receives actor fill")
		var changed: Dictionary = info.duplicate(true)
		# The immutable entry jamb is a layout key, not a door or moving lift.
		for solid: Dictionary in changed["solids"]:
			if is_equal_approx(float(solid["min_x"]), -8) and is_equal_approx(float(solid["max_x"]), -7.7 if mission == 12 else -7.6):
				solid["max_x"] = -7.0
		dressing.configure_map(changed)
		_expect(not dressing.active() and dressing.get_child_count() == 0, "reused id with moved walls receives no floating props")
		dressing.configure_map(info)
		var other: Dictionary = info.duplicate(true)
		other["map_id"] = 1
		dressing.configure_map(other)
		_expect(not dressing.active(), "leaving the mission clears its dressing")
		dressing.configure_map({"map_id":1012 if mission == 12 else 1013})
		_expect(not dressing.active(), "missing geometry is harmless")
		dressing.queue_free()
		# Integration boundary: same map and a state-related resend never
		# accumulate dressing. Solid views retain their collision-aligned size.
		var cover := ArenaCover.new()
		root.add_child(cover)
		cover.apply_map_info(info)
		var name: String = "HabitatDressing" if mission == 12 else "FoundryDressing"
		_expect(cover.has_node(name), "ArenaCover connects the authored presenter")
		var kept: Node = cover.get_node_or_null(name)
		cover.apply_map_info(info.duplicate(true))
		_expect(cover.get_node_or_null(name) == kept, "unchanged map keeps the cover")
		for view: MeshInstance3D in cover._solid_views:
			_expect(view.scale == Vector3.ONE, "no solid's visible hit volume shrinks")
			if view.material_override is ShaderMaterial:
				var material: ShaderMaterial = view.material_override
				var tint: Color = material.get_shader_parameter("surface_color")
				var accent: Color = material.get_shader_parameter("accent_color")
				_expect(not (tint.v >= 0.8 and tint.s <= 0.15), "walls never read as Inheritance off-white")
				_expect(not (accent.r > accent.g*1.5 and accent.r > accent.b*1.5), "infrastructure does not wear red attack markings")
				_expect(float(material.get_shader_parameter("trim_glow")) == 0.0, "painted marks never emit")
		var floor: Node = cover.get_node_or_null("LitFloor")
		_expect(floor != null, "foundation is divided for bounded local light")
		if floor != null:
			for child: Node in floor.get_children():
				var patch: MeshInstance3D = child as MeshInstance3D
				var plane: PlaneMesh = patch.mesh as PlaneMesh
				_expect(plane.size.x <= 8.0 and plane.size.y <= 8.0 and is_equal_approx(patch.position.y, 0.304), "small floor skins stay four millimetres above the real foundation")
		var resend: Dictionary = info.duplicate(true)
		resend["presentation"]["solids"][1] = "service_steel"
		cover.apply_map_info(resend)
		_expect(cover.find_children(name, "", false, false).size() == 1, "updated map has exactly one dressing")
		cover.queue_free()
	await process_frame
	if failures == 0:
		print("test_mars_dressing: PASS authored guards, resend lifecycle, unchanged geometry, local neutral lights and no invented facts")
	quit(0 if failures == 0 else 1)

static func habitat_fixture() -> Dictionary:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../server/maps/m12-terms-of-cooperation.json"))
	var solids: Array = []
	var surfaces: Array = []
	for solid: Dictionary in source["solids"]:
		solids.append({"min_x":solid["min"][0],"max_x":solid["max"][0],"min_z":solid["min"][2],"max_z":solid["max"][2],"bottom":solid["min"][1],"top":solid["max"][1]})
		surfaces.append(solid["surface"])
	return {"type":"map_info","map_id":1012,"map_name":source["name"],"geometry_version":2,"half_extent":source["half_extent"],"solids":solids,
		"m12":{},"presentation":{"ground":"concrete","solids":surfaces,"decorations":[]}}
