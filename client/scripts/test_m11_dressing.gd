extends SceneTree

var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("test_m11_dressing: " + message)

static func authored_info() -> Dictionary:
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://../server/maps/m11_right_of_search.json"))
	if not source is Dictionary:
		return {}
	var solids: Array = []
	var surfaces: Array = []
	var index_of: Dictionary = {}
	for solid: Dictionary in source["solids"]:
		index_of[solid["id"]] = solids.size()
		solids.append({"min_x": solid["min"][0], "max_x": solid["max"][0], "min_z": solid["min"][2], "max_z": solid["max"][2], "bottom": solid["min"][1], "top": solid["max"][1]})
		surfaces.append(solid["surface"])
	var decorations: Array = []
	for detail: Dictionary in source["decorations"]:
		var placed: Dictionary = detail.duplicate(true)
		placed["solid"] = index_of[detail["solid"]]
		decorations.append(placed)
	var authored: Dictionary = source["m11"]
	var facts: Dictionary = {}
	for key: String in ["transfer_release", "records_document", "departure"]:
		var panel: Dictionary = authored[key]["panel"].duplicate(true)
		panel["solid"] = index_of[panel["solid"]]
		decorations.append(panel)
		facts[key] = {"decoration": decorations.size() - 1, "approach": authored[key]["approach"]}
	var objectives: Array = []
	for objective: Dictionary in authored["objectives"]:
		objectives.append({"id": objective["id"], "action": {"kind": "arrival", "feet": objective["approach"], "region": objective["arrival"]}})
	facts["objectives"] = objectives
	for key: String in ["boarding", "companion_start", "transfer_people"]:
		facts[key] = authored[key]
	return {"type": "map_info", "geometry_version": 2, "map_id": source["map_id"], "map_name": source["name"], "half_extent": source["half_extent"], "solids": solids, "m11": facts,
		"presentation": {"ground": source["ground"], "solids": surfaces, "decorations": decorations}}

func _run() -> void:
	var info: Dictionary = authored_info()
	_check(MissionState.map_error(info).is_empty(), "authored fixture passes mission boundary")
	_check(M11Dressing.tender_layout(info), "authored tender recognized")
	var moved: Dictionary = info.duplicate(true)
	moved["solids"][0]["max_x"] = 11
	_check(not M11Dressing.tender_layout(moved), "changed hull with reused id gets no dressing")
	var other: Dictionary = info.duplicate(true)
	other["map_id"] = 1010
	_check(not M11Dressing.tender_layout(other), "Carrier gets no tender dressing")
	_check(not M11Dressing.tender_layout({"map_id": 1011}), "incomplete map refused")
	var presenter: M11Tender = M11Tender.new()
	root.add_child(presenter)
	presenter.configure_map(info)
	_check(presenter.dressing != null and presenter.dressing.active(), "tender presenter attaches dressed rooms")
	var count: int = presenter.get_child_count()
	presenter.configure_map(info.duplicate(true))
	_check(presenter.get_child_count() == count and presenter._people.size() == 3, "map resend never duplicates dressing or people")
	var dressing: M11Dressing = presenter.dressing
	for room: String in ["Spine", "Armory", "Mess", "Transfer", "Records", "Service", "Bridge"]:
		_check(dressing.has_node(room), "working region exists: " + room)
	_check(dressing.find_children("*", "CollisionObject3D", true, false).is_empty(), "dressing adds no collision")
	_check(dressing.find_children("*", "Label3D", true, false).is_empty(), "no extra readable signs")
	for light: Node in dressing.find_children("*", "OmniLight3D", true, false):
		var lamp: OmniLight3D = light as OmniLight3D
		_check(not lamp.shadow_enabled and lamp.omni_range <= 7.0, "practical lights stay local")
		_check(lamp.light_color.r > 0.8 and lamp.light_color.g > 0.8 and lamp.light_color.b > 0.6, "neutral and warm work light preserve red enemy optics")
	for visual: Node in dressing.find_children("*", "VisualInstance3D", true, false):
		_check(((visual as VisualInstance3D).layers & ArenaSky.ACTOR_LAYERS) == 0, "dressing never receives actor-only fill")
	var cover: ArenaCover = ArenaCover.new()
	root.add_child(cover)
	cover.apply_map_info(info)
	_check(cover._solid_views.size() == info["solids"].size(), "every authoritative solid keeps its visual")
	for index: int in range(cover._solid_views.size()):
		var view: MeshInstance3D = cover._solid_views[index]
		if info["presentation"]["solids"][index] == "inspection_glass":
			_check(view.material_override is StandardMaterial3D and (view.material_override as StandardMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "Carrier remains visible through glass")
		else:
			_check(view.material_override is ShaderMaterial, "solid keeps textured shader")
			if view.material_override is ShaderMaterial:
				var material: ShaderMaterial = view.material_override
				_check(material.get_shader_parameter("trim_glow") == 0.0, "paint never emits red tell light")
				var tint: Color = material.get_shader_parameter("surface_color")
				_check(tint.v < 0.8, "tender does not read as Inheritance off-white")
	presenter.configure_map(moved)
	_check(presenter.dressing == null, "changed layout retires dressing")
	var invalid: Dictionary = info.duplicate(true)
	invalid["m11"].erase("departure")
	presenter.configure_map(invalid)
	_check(presenter.get_child_count() == 0, "refused mission map clears presentation")
	presenter.configure_map(info)
	presenter.clear_map()
	_check(presenter.get_child_count() == 0 and presenter.dressing == null, "leaving retires all rooms and lights")
	presenter.queue_free()
	cover.queue_free()
	await process_frame
	await process_frame
	if failures == 0:
		print("test_m11_dressing: PASS layout guards, map resend, retirement, quiet surfaces, local light, no words or collision")
	quit(0 if failures == 0 else 1)
