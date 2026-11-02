extends SceneTree

## Static fixtures merge into one mesh with one surface per finish. Turned
## parts (lathe, rod, cylinder, pipe) and boxes or imported meshes that share
## a finish must all survive the merge: a merged surface that keeps only one
## layout's triangles silently hides the rest of a room's props.
const Geometry = preload("res://scripts/model_geometry.gd")
var _failures: PackedStringArray = []

func _initialize() -> void:
	set_meta("localexception_automated", true)
	_run.call_deferred()

static func triangles(mesh: Mesh, surface: int) -> int:
	var arrays: Array = mesh.surface_get_arrays(surface)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	return (indices.size() if not indices.is_empty() else vertices.size()) / 3

## Every triangle a merged surface draws, as world-space positions.
static func drawn_points(mesh: Mesh, surface: int) -> PackedVector3Array:
	var arrays: Array = mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if indices.is_empty():
		return vertices
	var drawn: PackedVector3Array = []
	for index: int in indices:
		drawn.append(vertices[index])
	return drawn

func _run() -> void:
	var shape: RefCounted = Geometry.new()
	var parent: Node3D = Node3D.new()
	root.add_child(parent)
	var shared: StandardMaterial3D = shape.material("merge_shared", Color("56635a"))
	var turned_only: StandardMaterial3D = shape.material("merge_turned", Color("2f3533"))
	# Box first (indexed primitive), then turned parts on the same finish.
	MoonBackdrop._piece(parent, "Box", Vector3(0, 0.5, 0), Vector3(1, 1, 1), shared)
	shape.rod(parent, "Rod", Vector3(3, 0.5, 0), Vector3(5, 0.5, 0), 0.2, shared, 8)
	shape.cylinder(parent, "Cylinder", 0.3, 0.1, shared, Vector3(-4, 1, 0), 8)
	# And the reverse order on its own finish: turned part first, box after.
	shape.rod(parent, "RodFirst", Vector3(0, 3, -3), Vector3(0, 3, -6), 0.1, turned_only, 6)
	MoonBackdrop._piece(parent, "BoxAfter", Vector3(0, 3, 4), Vector3(0.5, 0.5, 0.5), turned_only)
	var expected: Dictionary[StandardMaterial3D, int] = {}
	for child: Node in parent.get_children():
		var piece: MeshInstance3D = child as MeshInstance3D
		var finish: StandardMaterial3D = piece.material_override as StandardMaterial3D
		for surface: int in range(piece.mesh.get_surface_count()):
			expected[finish] = expected.get(finish, 0) + triangles(piece.mesh, surface)
	shape.merge(parent)
	_expect(parent.get_child_count() == 1, "pieces collapse into one fixture mesh")
	var merged: MeshInstance3D = parent.get_child(0) as MeshInstance3D
	_expect(merged != null and merged.mesh.get_surface_count() == 2, "one surface per finish")
	if merged != null:
		for surface: int in range(merged.mesh.get_surface_count()):
			var finish: StandardMaterial3D = merged.mesh.surface_get_material(surface) as StandardMaterial3D
			_expect(triangles(merged.mesh, surface) == expected.get(finish, -1),
				"%s keeps every triangle: %d of %d" % [finish.resource_name, triangles(merged.mesh, surface), expected.get(finish, -1)])
			var drawn: PackedVector3Array = drawn_points(merged.mesh, surface)
			var reach: PackedVector3Array = PackedVector3Array([Vector3(5, 0.5, 0), Vector3(-4, 1, 0)]) if finish == shared \
				else PackedVector3Array([Vector3(0, 3, -6), Vector3(0, 3, 4)])
			for point: Vector3 in reach:
				var near: bool = false
				for vertex: Vector3 in drawn:
					if vertex.distance_to(point) < 0.6:
						near = true
						break
				_expect(near, "%s still draws the part at %s" % [finish.resource_name, point])
	parent.free()
	for failure: String in _failures:
		push_error("test_fixture_merge: " + failure)
	if _failures.is_empty():
		print("test_fixture_merge: PASS turned parts and boxes sharing a finish all survive the merge")
	quit(0 if _failures.is_empty() else 1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
