extends SceneTree

var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("test_m06_port_activity: " + message)

func _run() -> void:
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://../server/maps/m06_port_of_entry.json"))
	_check(doc is Dictionary, "actual authored port source loads")
	if not doc is Dictionary:
		quit(1)
		return
	var solids: Array[Dictionary] = []
	for solid: Dictionary in doc["solids"]:
		solids.append({"min_x": solid["min"][0], "max_x": solid["max"][0], "min_z": solid["min"][2],
			"max_z": solid["max"][2], "bottom": solid["min"][1], "top": solid["max"][1]})
	var info: Dictionary = {"map_id": 1006, "map_name": "Port of Entry", "solids": solids}
	var activity: M06PortActivity = M06PortActivity.new()
	root.add_child(activity)
	activity.build(info)
	_check(activity.host_count == 10, "ten real machine/work hosts select their fitting assemblies")
	_check(activity.get_child_count() <= 45, "coherent work-area dressing has a finite budget")
	var displays: int = 0
	var luggage: bool = false
	for child: Node in activity.get_children():
		_check(child is MeshInstance3D, "activity creates no cosmetic collision, simulated workers or new lights")
		if not child is MeshInstance3D:
			continue
		var view: MeshInstance3D = child
		var material: StandardMaterial3D = view.material_override
		_check(view.layers == 2 and material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST,
			"work-area finish uses nearest-filtered world lighting")
		var low: Vector3 = view.get_meta("m06_activity_low") - Vector3.ONE * M06PortActivity.TRIM
		var high: Vector3 = view.get_meta("m06_activity_high") + Vector3.ONE * M06PortActivity.TRIM
		var bounds: AABB = view.mesh.get_aabb()
		for x: float in [0.0, 1.0]:
			for y: float in [0.0, 1.0]:
				for z: float in [0.0, 1.0]:
					var point: Vector3 = view.transform * (bounds.position + bounds.size * Vector3(x, y, z))
					_check(point.x >= low.x and point.x <= high.x and point.y >= low.y and point.y <= high.y
						and point.z >= low.z and point.z <= high.z, "full rotated finish lies in its actual host plus shallow trim: " + str(view.name))
		if view.mesh is QuadMesh:
			displays += 1
			_check(material.albedo_texture != null and material.albedo_texture.get_size() == Vector2(64, 32),
				"authored display uses a bounded original pixel icon")
		if material.albedo_texture != null and material.albedo_texture.resource_path == M06Port.TEXTILE:
			luggage = true
	_check(displays == 3 and luggage, "scale console, both actual desks and personal textile are present")
	for patch: Dictionary in [{"map_id": 1007}, {"map_name": "Declared Goods"}, {"solids": []}]:
		var other: Dictionary = info.duplicate(true)
		other.merge(patch, true)
		var rejected: M06PortActivity = M06PortActivity.new()
		rejected.build(other)
		_check(rejected.get_child_count() == 0, "another venue or unregistered platform cannot gain machinery")
		rejected.free()
	activity.queue_free()
	await process_frame
	if failures == 0:
		print("test_m06_port_activity: PASS actual hosts, rotated bounds, pixel displays, materials and cleanup")
	quit(0 if failures == 0 else 1)
