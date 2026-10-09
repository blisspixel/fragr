extends RefCounted

## Offline authored-pose support. This never adjusts a live actor or collision.
static func minimum_y(node: Node3D, parent: Transform3D = Transform3D.IDENTITY) -> float:
	var transform: Transform3D = parent * node.transform
	var lowest: float = INF
	if node is MeshInstance3D and node.mesh != null:
		for surface: int in range(node.mesh.get_surface_count()):
			var vertices: PackedVector3Array = node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex: Vector3 in vertices:
				lowest = minf(lowest, (transform * vertex).y)
	for child: Node in node.get_children():
		if child is Node3D:
			lowest = minf(lowest, minimum_y(child, transform))
	return lowest

static func lift_to_floor(node: Node3D) -> float:
	var lowest: float = minimum_y(node)
	var lift: float = maxf(0.0, -lowest) if is_finite(lowest) else 0.0
	node.position.y += lift
	return lift
