extends SceneTree

const MissionFixture: Script = preload("res://scripts/test_m10_mission.gd")
var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("test_ship_furnishings: " + message)

func _run() -> void:
	var source: Node3D = ShipFurnishings.instantiate_source()
	_check(source != null and ShipFurnishings.source_error(source).is_empty(), "packaged source retains embedded nearest paint, normals and real dimensions")
	if source != null:
		var mesh: MeshInstance3D = source.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		var material: StandardMaterial3D = mesh.get_active_material(0) as StandardMaterial3D
		var original_normal: Texture2D = material.normal_texture
		material.normal_texture = null
		_check(not ShipFurnishings.source_error(source).is_empty(), "missing normal map cannot hide physical proxy")
		material.normal_texture = original_normal
		var original_mesh: Mesh = mesh.mesh
		mesh.mesh = BoxMesh.new()
		_check(not ShipFurnishings.source_error(source).is_empty(), "wrong source geometry cannot substitute for measured furniture")
		mesh.mesh = original_mesh
		var weak_source: WeakRef = weakref(source)
		source.free()
		_check(weak_source.get_ref() == null, "packaged source has explicit teardown")
	var parent: Node3D = Node3D.new()
	root.add_child(parent)
	var proxy: MeshInstance3D = MeshInstance3D.new()
	proxy.mesh = BoxMesh.new()
	parent.add_child(proxy)
	var views: Array[MeshInstance3D] = [proxy]
	var old_map: Dictionary = MissionFixture.fixture_map()
	_check(ShipFurnishings.build(parent, old_map, views) == null and proxy.visible, "unmatched accepted older ship keeps visible physical proxy")
	var invalid: Dictionary = old_map.duplicate(true)
	invalid["solids"][0]["min_x"] = "untrusted"
	_check(ShipFurnishings.build(parent, invalid, views) == null and proxy.visible, "malformed map cannot hide proxy or create source")
	invalid = old_map.duplicate(true)
	invalid.erase("m10")
	_check(ShipFurnishings.build(parent, invalid, views) == null and proxy.visible, "other venues do not acquire ship art")
	old_map["solids"][0].erase("bottom")
	old_map["solids"][0].erase("top")
	_check(ShipFurnishings.matched_host(old_map).is_empty(), "legacy omitted heights refuse safely without invalid indexing")
	parent.free()
	await process_frame
	if failures == 0:
		print("test_ship_furnishings: PASS")
	quit(0 if failures == 0 else 1)
