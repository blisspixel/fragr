extends SceneTree

var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("test_m06_workmanship: " + message)

func _run() -> void:
	var authored: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://../server/maps/m06_port_of_entry.json"))
	_check(authored is Dictionary, "real port source loads")
	if not authored is Dictionary:
		quit(1)
		return
	var solids: Array[Dictionary] = []
	for solid: Dictionary in authored["solids"]:
		solids.append({"min_x": solid["min"][0], "max_x": solid["max"][0], "min_z": solid["min"][2],
			"max_z": solid["max"][2], "bottom": solid["min"][1], "top": solid["max"][1]})
	var info: Dictionary = {"map_id": 1006, "map_name": "Port of Entry", "solids": solids}
	var details: M06Workmanship = M06Workmanship.new()
	root.add_child(details)
	details.build(info)
	_check(details.mesh_count > 100 and details.mesh_count <= 160 and details.light_count <= 8,
		"authored workmanship stays within finite mesh and practical-light budgets")
	_check(details.get_children().filter(func(child: Node) -> bool: return child.get_meta("m06_detail_kind", "") == "CargoSealedLatch").size() == 4,
		"only four existing freight bodies receive cargo treatment")
	_check(details.get_children().filter(func(child: Node) -> bool: return child.get_meta("m06_detail_kind", "") == "InspectionWorkMat").size() == 4,
		"real customs and transit bodies keep their distinct work surfaces")
	for child: Node in details.get_children():
		_check(not child is CollisionObject3D, "presentation introduces no collision objects")
		if child is OmniLight3D:
			var light: OmniLight3D = child
			_check(light.position.y > 5.7 and light.light_cull_mask == 2
				and light.is_in_group(ArenaSky.PRACTICAL_GROUP), "overhead practical stays world-only and quality-managed")
		if not child is MeshInstance3D:
			continue
		var mesh: MeshInstance3D = child
		_check(mesh.layers == 2, "solid dressing uses the world visual layer")
		var material: StandardMaterial3D = mesh.material_override
		_check(material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST
			and material.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED,
			"broad stylized finishes remain nearest filtered and respond to real light")
		if mesh.has_meta("m06_host_low"):
			var low: Vector3 = mesh.get_meta("m06_host_low") - Vector3.ONE * M06Workmanship.MAX_TRIM
			var high: Vector3 = mesh.get_meta("m06_host_high") + Vector3.ONE * M06Workmanship.MAX_TRIM
			var bounds: AABB = mesh.mesh.get_aabb()
			_check(low.x <= bounds.position.x + mesh.position.x and high.x >= bounds.end.x + mesh.position.x
				and low.y <= bounds.position.y + mesh.position.y and high.y >= bounds.end.y + mesh.position.y
				and low.z <= bounds.position.z + mesh.position.z and high.z >= bounds.end.z + mesh.position.z,
				"full trim bounds remain in the registered host's 25 mm surface allowance: " + str(mesh.name))
		else:
			_check(mesh.position.y < 0.01 and is_equal_approx((mesh.mesh as BoxMesh).size.y, 0.006),
				"unhosted detail is flush floor paint")
	for patch: Dictionary in [{"map_id": 1007}, {"map_name": "Declared Goods"}, {"solids": []},
		{"solids": preload("res://scripts/test_m06_mission.gd").fixture_map()["solids"]}]:
		var other: Dictionary = info.duplicate(true)
		other.merge(patch, true)
		var rejected: M06Workmanship = M06Workmanship.new()
		rejected.build(other)
		_check(rejected.mesh_count == 0 and rejected.light_count == 0,
			"different venue and synthetic footprints cannot gain authored port fittings")
		rejected.free()
	var count: int = get_nodes_in_group(ArenaSky.PRACTICAL_GROUP).size()
	details.queue_free()
	await process_frame
	_check(get_nodes_in_group(ArenaSky.PRACTICAL_GROUP).size() == count - 8,
		"map replacement removes every workmanship practical")
	if failures == 0:
		print("test_m06_workmanship: PASS real hosts, flush trim, finite budgets, venue guard and cleanup")
	quit(0 if failures == 0 else 1)
