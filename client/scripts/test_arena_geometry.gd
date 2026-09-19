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
	if (layout.get_node("Floor") as Node3D).visible or cover.get_child_count() != 7:
		push_error("test_arena_geometry: replacement revived or duplicated geometry")
		ok = false
	arena.free()
	if ok:
		print("test_arena_geometry: PASS bounds, cover, legacy removal, replacement")
	quit(0 if ok else 1)
