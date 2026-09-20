extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var arena: Node3D = Node3D.new()
	root.add_child(arena)
	var scene: PackedScene = load("res://scenes/arena.tscn")
	var layout: Node3D = scene.instantiate()
	layout.name = "Layout"
	arena.add_child(layout)
	var cover: ArenaCover = ArenaCover.new()
	arena.add_child(cover)
	var info: Dictionary = {"map_id": 5, "half_extent": 100.0, "solids": [
		{"min_x": 10.0, "max_x": 14.0, "min_z": 20.0, "max_z": 26.0, "top": 0.5},
		{"min_x": -10.0, "max_x": -8.0, "min_z": 0.0, "max_z": 4.0, "top": 6.0},
	]}
	cover.apply_map_info(info)
	var ok: bool = true
	for legacy: String in ["Floor", "WallNorth", "LowWallWest", "ZoneCenter"]:
		if (layout.get_node(legacy) as Node3D).visible:
			push_error("test_arena_geometry: legacy geometry still visible: " + legacy)
			ok = false
	var floor_node: MeshInstance3D = cover.get_node("MapFloor")
	if (floor_node.mesh as PlaneMesh).size != Vector2(200.0, 200.0):
		push_error("test_arena_geometry: floor does not match server bounds")
		ok = false
	var step: MeshInstance3D = cover.get_child(5)
	if step.position != Vector3(12.0, 0.25, 23.0) or (step.mesh as BoxMesh).size != Vector3(4.0, 0.5, 6.0):
		push_error("test_arena_geometry: step does not match server solid")
		ok = false
	# Snapshot layout replacement must not revive the old geometry, even when
	# MapInfo arrived first and the geometry builder has already seen this id.
	arena.remove_child(layout)
	layout.free()
	layout = scene.instantiate()
	layout.name = "Layout"
	arena.add_child(layout)
	cover.apply_map_info(info)
	if (layout.get_node("Floor") as Node3D).visible or cover.get_child_count() != 8:
		push_error("test_arena_geometry: replacement revived or duplicated geometry")
		ok = false
	# Decorations must not create apparent cover inside the playable square.
	var backdrop: ArenaBackdrop = cover.get_node("Backdrop")
	for child: Node in backdrop.get_children():
		if child is MeshInstance3D:
			var mesh_node: MeshInstance3D = child
			var box: AABB = mesh_node.transform * mesh_node.get_aabb()
			if box.position.x < 100.0 and box.end.x > -100.0 and box.position.z < 100.0 and box.end.z > -100.0:
				push_error("test_arena_geometry: scenery intrudes on playable space")
				ok = false
	# Rotation replaces old meshes immediately, with no overlapping frame.
	cover.apply_map_info({"map_id": 7, "half_extent": 20.0, "solids": [
		{"min_x": -2.0, "max_x": 2.0, "min_z": -3.0, "max_z": 3.0, "bottom": 2.4, "top": 3.0},
	]})
	var deck: MeshInstance3D = cover.get_child(5)
	if not deck.position.is_equal_approx(Vector3(0.0, 2.7, 0.0)) or not (deck.mesh as BoxMesh).size.is_equal_approx(Vector3(4.0, 0.6, 6.0)):
		push_error("test_arena_geometry: raised floor fills its underpass")
		ok = false
	cover.apply_map_info({"map_id": 2, "half_extent": 55.0, "solids": []})
	if cover.get_child_count() != 6 or (cover.get_node("MapFloor").mesh as PlaneMesh).size != Vector2(110.0, 110.0):
		push_error("test_arena_geometry: map rotation retained stale geometry")
		ok = false
	arena.free()
	if ok:
		print("test_arena_geometry: PASS bounds, cover, legacy removal, replacement")
	quit(0 if ok else 1)
