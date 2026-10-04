extends SceneTree

const LivedDetail = preload("res://scripts/m04_lived_detail.gd")
var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _run() -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://../server/maps/m04_notice_to_vacate.json"))
	_check(raw is Dictionary, "loads actual authored M04")
	if not raw is Dictionary:
		quit(1)
		return
	var solids: Array[Dictionary] = []
	for solid: Dictionary in raw["solids"]:
		solids.append({"min_x": solid["min"][0], "bottom": solid["min"][1], "min_z": solid["min"][2],
			"max_x": solid["max"][0], "top": solid["max"][1], "max_z": solid["max"][2]})
	var parent: Node3D = Node3D.new()
	root.add_child(parent)
	var detail: Node3D = LivedDetail.new().build(parent, {"solids": solids})
	_check(detail.has_node("SharedChargingBench") and detail.has_node("MaintainedCareStation")
		and detail.has_node("InterruptedSharedMeal"), "specific activities anchor to actual solid furniture")
	_check(detail.get_meta("finish_surfaces") <= 8, "merged material surfaces bound render submissions")
	var mesh_nodes: int = 0
	var windows: int = 0
	var beds: int = 0
	for child: Node in detail.get_children():
		_check(not child is CollisionObject3D, "presentation adds no collision or gameplay object")
		if child is MeshInstance3D:
			mesh_nodes += 1
			_check(child.layers == ArenaSky.WORLD_LAYERS, "world detail receives venue lighting")
		if child.name.begins_with("SealedDomesticWindow"):
			windows += 1
		if child.name.begins_with("ClinicMadeBed"):
			beds += 1
	_check(mesh_nodes == 1 and windows == 9 and beds == 2, "single merged mesh, nine sealed homes, two made beds")
	# Inspect every final vertex rather than assuming the chosen primitives stay
	# within the wall face or furniture footprint after rotations and merging.
	for index: int in range(solids.size()):
		var solid: Dictionary = solids[index]
		var individual: Node3D = LivedDetail.new().build(parent, {"solids": [solid]})
		if not individual.has_node("MergedPossessions"):
			individual.free()
			continue
		var mesh: ArrayMesh = individual.get_node("MergedPossessions").mesh
		for surface: int in range(mesh.get_surface_count()):
			var vertices: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for point: Vector3 in vertices:
				if individual.get_child(0).name.begins_with("SealedDomesticWindow"):
					_check(point.x >= float(solid["min_x"]) - 0.0081 and point.x <= float(solid["max_x"]) + 0.0081
						and point.z >= float(solid["min_z"]) - 0.0081 and point.z <= float(solid["max_z"]) + 0.0081,
						"sealed homes project at most eight millimetres from the registered wall")
				else:
					_check(point.x >= float(solid["min_x"]) - 0.001 and point.x <= float(solid["max_x"]) + 0.001
						and point.z >= float(solid["min_z"]) - 0.001 and point.z <= float(solid["max_z"]) + 0.001
						and point.y >= float(solid["top"]) - 0.001 and point.y <= float(solid["top"]) + 0.3,
						"small possessions stay on existing furniture and out of movement lanes")
		individual.free()
	var unrelated: Node3D = LivedDetail.new().build(parent, {"solids": [{"min_x": 1, "max_x": 5, "min_z": 1, "max_z": 5, "bottom": 0, "top": 1}]})
	_check(unrelated.get_child_count() == 0 and unrelated.get_meta("source_parts") == 0,
		"unrecognized custom M04 solids do not inherit guessed dressing")
	parent.free()
	if failures == 0:
		print("test_m04_lived_detail: PASS actual furniture bounds, sealed homes, merged world materials and custom-map restraint")
	quit(0 if failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		if failures < 8:
			push_error("test_m04_lived_detail: " + message)
