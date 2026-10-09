extends RefCounted

## Caps use actual original cut edges. Original source faces are never replaced.
const GlbData = preload("res://../tools/tern_glb.gd")
const Access = preload("res://../tools/edda_skin_repair.gd")
const RawAudit = preload("res://../tools/audit_splice_source.gd")

static func build(rig: Dictionary, faces: Array[PackedInt32Array], parents: PackedInt32Array, moving: PackedInt32Array) -> Dictionary:
	var raw: Dictionary = GlbData.read(RawAudit.SOURCE)
	var primitive: Dictionary = raw.document.meshes[0].primitives[0]
	var positions: Dictionary = Access.accessor(raw.document, int(primitive.attributes.POSITION), 5126, "VEC3", RawAudit.VERTICES)
	var indices: Dictionary = Access.accessor(raw.document, int(primitive.indices), 5123, "SCALAR", RawAudit.TRIANGLES * 3)
	var points: PackedVector3Array = []
	var mapping: PackedInt32Array = []
	var cells: Dictionary[Vector3i, int] = {}
	for vertex: int in RawAudit.VERTICES:
		var at: int = int(positions.offset) + vertex * int(positions.stride)
		var point: Vector3 = Vector3(raw.binary.decode_float(at), raw.binary.decode_float(at + 4), raw.binary.decode_float(at + 8))
		var cell: Vector3i = Vector3i((point * 1000000.0).round())
		if not cells.has(cell):
			cells[cell] = points.size()
			points.append(point)
		mapping.append(cells[cell])
	var edges: Dictionary[Vector2i, Dictionary] = {}
	for part: int in faces.size():
		for face: int in faces[part]:
			var ids: PackedInt32Array = []
			for corner: int in 3:
				ids.append(mapping[raw.binary.decode_u16(int(indices.offset) + (face * 3 + corner) * int(indices.stride))])
			for corner: int in 3:
				var edge: Vector2i = Vector2i(mini(ids[corner], ids[(corner + 1) % 3]), maxi(ids[corner], ids[(corner + 1) % 3]))
				if not edges.has(edge):
					edges[edge] = {}
				edges[edge][part] = int(edges[edge].get(part, 0)) + 1
	var closures: Dictionary[int, Array] = {}
	var rows: Array[Dictionary] = []
	var total: int = 0
	var dark: StandardMaterial3D = StandardMaterial3D.new()
	dark.albedo_color = Color("242728")
	dark.roughness = 1.0
	dark.cull_mode = BaseMaterial3D.CULL_DISABLED
	for child: int in moving:
		var parent: int = parents[child]
		var pair: Array = []
		for owner: int in [parent, child]:
			var vertices: PackedVector3Array = []
			var normals: PackedVector3Array = []
			var original_points: PackedVector3Array = []
			var capped: int = 0
			var already_closed: int = 0
			var degenerate: int = 0
			for edge: Vector2i in edges:
				var owners: Dictionary = edges[edge]
				if not owners.has(parent) or not owners.has(child):
					continue
				if int(owners[owner]) != 1:
					already_closed += 1
					continue
				var a: Vector3 = points[edge.x]
				var b: Vector3 = points[edge.y]
				var center: Vector3 = rig.pivots[child]
				var cross: Vector3 = (b - a).cross(center - a)
				if cross.length_squared() <= 0.000000000000000000000004:
					degenerate += 1
					continue
				vertices.append_array(PackedVector3Array([a, b, center]))
				var normal: Vector3 = cross.normalized()
				normals.append_array(PackedVector3Array([normal, normal, normal]))
				original_points.append(a)
				original_points.append(b)
				capped += 1
			if vertices.is_empty() or degenerate > 0:
				return {}
			var arrays: Array = []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = vertices
			arrays[Mesh.ARRAY_NORMAL] = normals
			var mesh: ArrayMesh = ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var node: MeshInstance3D = MeshInstance3D.new()
			node.name = "OriginalEdgeClosure_%d_%d" % [child, owner]
			node.mesh = mesh
			node.material_override = dark
			rig.parts[owner].add_child(node)
			node.position = -rig.pivots[owner]
			pair.append({"node":node, "owner":owner, "original_points":original_points, "center":rig.pivots[child]})
			total += capped
			rows.append({"joint_child":child, "owner":owner, "added_closure_triangles":capped, "original_nonmanifold_edges_already_closed":already_closed, "new_degenerate_triangles":degenerate})
		closures[child] = pair
	return {"nodes":closures, "rows":rows, "added_triangles":total}

static func measure(rig: Dictionary, closures: Dictionary) -> Dictionary:
	var maximum_rim_error: float = 0.0
	var maximum_center_error: float = 0.0
	var complete: bool = true
	for child: int in closures:
		var centers: PackedVector3Array = []
		for cap: Dictionary in closures[child]:
			var node: MeshInstance3D = cap.node
			complete = complete and node.visible
			centers.append(node.global_transform * cap.center)
			for point: Vector3 in cap.original_points:
				var source: Vector3 = rig.meshes[cap.owner].global_transform * point
				var closure: Vector3 = node.global_transform * point
				maximum_rim_error = maxf(maximum_rim_error, source.distance_to(closure))
		if centers.size() != 2:
			complete = false
		else:
			maximum_center_error = maxf(maximum_center_error, centers[0].distance_to(centers[1]))
	complete = complete and maximum_rim_error <= 0.000001 and maximum_center_error <= 0.000001
	return {"complete":complete, "maximum_cap_to_original_rim_error_m":maximum_rim_error, "maximum_common_joint_center_error_m":maximum_center_error}
