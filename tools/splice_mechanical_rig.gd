extends RefCounted

## Offline rigid source candidate. No runtime registry or campaign selection.
const GlbData = preload("res://../tools/tern_glb.gd")
const Access = preload("res://../tools/edda_skin_repair.gd")
const RawAudit = preload("res://../tools/audit_splice_source.gd")
const Regions = preload("res://../tools/refine_splice_partition.gd")
const Closure = preload("res://../tools/splice_joint_closure.gd")
const PARENTS: PackedInt32Array = [1, 2, 3, -1, 2, 4, 5, 2, 7, 8, 3, 10, 11, 3, 13, 14, 13]
const MOVING: PackedInt32Array = [0, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]

static func build(directory: String, expected_sha: String) -> Dictionary:
	var manifest_file: FileAccess = FileAccess.open(directory.path_join("partition.json"), FileAccess.READ)
	if manifest_file == null or FileAccess.get_sha256(RawAudit.SOURCE) != RawAudit.SHA:
		return {}
	var manifest_value: Variant = JSON.parse_string(manifest_file.get_as_text())
	if not manifest_value is Dictionary:
		return {}
	var manifest: Dictionary = manifest_value
	var path: String = directory.path_join("labels.glb")
	if manifest.get("diagnostic_sha256") != expected_sha or FileAccess.get_sha256(path) != expected_sha or manifest.rows.size() != Regions.PARTS.size() or int(manifest.boundaries.unwanted_parent_interfaces) != 0:
		return {}
	var raw: Dictionary = GlbData.read(RawAudit.SOURCE)
	var faces: Array[PackedInt32Array] = []
	for row: Dictionary in manifest.rows:
		faces.append(PackedInt32Array(row.original_triangle_ids))
	if not Regions.verify_coverage(raw, GlbData.read(path), faces) or not Regions.verify_identity(raw, faces):
		return {}
	var original: Node3D = _load(RawAudit.SOURCE)
	var labeled: Node3D = _load(path)
	if original == null or labeled == null:
		if original != null:
			original.free()
		if labeled != null:
			labeled.free()
		return {}
	var original_mesh: MeshInstance3D = original.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var material: Material = original_mesh.mesh.surface_get_material(0)
	var original_arrays: Array = original_mesh.mesh.surface_get_arrays(0)
	var original_points: PackedVector3Array = original_arrays[Mesh.ARRAY_VERTEX]
	var original_min: float = INF
	var original_max: float = -INF
	for point: Vector3 in original_points:
		original_min = minf(original_min, point.y)
		original_max = maxf(original_max, point.y)
	var scale_factor: float = 1.8 / (original_max - original_min)
	var model: Node3D = Node3D.new()
	model.name = "SpliceSourceCandidate"
	model.scale = Vector3.ONE * scale_factor
	var pivots: PackedVector3Array = []
	var radii: PackedFloat32Array = []
	for part: int in Regions.PARTS.size():
		pivots.append(Vector3.ZERO)
		radii.append(0.0)
	for child: int in Regions.PARTS.size():
		var parent: int = PARENTS[child]
		if parent < 0 or child == 16:
			continue
		for boundary: Dictionary in manifest.boundaries.interfaces:
			if Regions.PARTS[child] in boundary.parts and Regions.PARTS[parent] in boundary.parts:
				pivots[child] = Vector3(boundary.edge_end_mean[0], boundary.edge_end_mean[1], boundary.edge_end_mean[2])
				radii[child] = float(boundary.maximum_boundary_radius_m) + 0.003
				break
		if radii[child] <= 0.003:
			model.free()
			original.free()
			labeled.free()
			return {}
	pivots[16] = pivots[13]
	var parts: Array[Node3D] = []
	var meshes: Array[MeshInstance3D] = []
	var vertices: Array[PackedVector3Array] = []
	for part: int in Regions.PARTS.size():
		var pivot: Node3D = Node3D.new()
		pivot.name = Regions.PARTS[part]
		parts.append(pivot)
		var mesh: MeshInstance3D = labeled.find_child(Regions.PARTS[part], true, false) as MeshInstance3D
		if mesh == null:
			# GLTF nodes may own a differently named mesh child.
			var node: Node = labeled.find_child(Regions.PARTS[part], true, false)
			if node != null:
				var children: Array[Node] = node.find_children("*", "MeshInstance3D", true, false)
				if children.size() == 1:
					mesh = children[0] as MeshInstance3D
		if mesh == null:
			model.free()
			original.free()
			labeled.free()
			for detached: Node3D in parts:
				if not detached.is_inside_tree():
					detached.free()
			return {}
		mesh.get_parent().remove_child(mesh)
		mesh.owner = null
		pivot.add_child(mesh)
		mesh.position = -pivots[part]
		mesh.set_surface_override_material(0, material)
		meshes.append(mesh)
		var arrays: Array = mesh.mesh.surface_get_arrays(0)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var used: Dictionary[int, bool] = {}
		var measured: PackedVector3Array = []
		for index: int in indices:
			if not used.has(index):
				used[index] = true
				measured.append(points[index])
		vertices.append(measured)
	for child: int in Regions.PARTS.size():
		var parent: int = PARENTS[child]
		if parent < 0:
			model.add_child(parts[child])
		else:
			parts[parent].add_child(parts[child])
			parts[child].position = pivots[child] - pivots[parent]
	var context: Dictionary = {"root":model, "parts":parts, "meshes":meshes, "pivots":pivots}
	var closure: Dictionary = Closure.build(context, faces, PARENTS, MOVING)
	if closure.is_empty():
		model.free()
		original.free()
		labeled.free()
		return {}
	var witnesses: Dictionary = _boundary_witnesses(raw, faces)
	original.free()
	labeled.free()
	return {"root":model, "parts":parts, "meshes":meshes, "vertices":vertices, "pivots":pivots, "radii":radii, "closures":closure.nodes, "closure_rows":closure.rows, "witnesses":witnesses, "scale":scale_factor, "original_min":original_min, "original_triangles":RawAudit.TRIANGLES, "added_closure_triangles":closure.added_triangles, "candidate_sha256":expected_sha}

static func pose(rig: Dictionary, phase: float, walking: bool = true) -> void:
	for part: Node3D in rig.parts:
		part.rotation = Vector3.ZERO
	var parts: Array[Node3D] = rig.parts
	var wave: float = sin(phase * TAU)
	if walking:
		for side: int in 2:
			var swing: float = wave if side == 0 else -wave
			var hip: int = 10 if side == 0 else 13
			var lower: int = 11 if side == 0 else 14
			var foot: int = 12 if side == 0 else 15
			var upper_arm: int = 4 if side == 0 else 7
			var forearm: int = 5 if side == 0 else 8
			parts[hip].rotation.x = deg_to_rad(14.0 * swing)
			parts[lower].rotation.x = deg_to_rad(22.0 * maxf(-swing, 0.0))
			parts[foot].rotation.x = -parts[hip].rotation.x - parts[lower].rotation.x
			parts[upper_arm].rotation.x = deg_to_rad(-8.0 * swing)
			parts[forearm].rotation.x = deg_to_rad(-5.0 * absf(wave))
		parts[2].rotation.y = deg_to_rad(sin(phase * TAU * 2.0) * 1.2)
	parts[0].rotation.y = deg_to_rad(wave * 14.0)
	# Source support, never movement authority. Measure indexed original vertices
	# in the actually posed hierarchy, then register its lowest transformed sole.
	rig.root.position.y = 0.0
	var minimum: float = INF
	for foot: int in [12, 15]:
		for point: Vector3 in rig.vertices[foot]:
			minimum = minf(minimum, (rig.meshes[foot].global_transform * point).y)
	rig.root.position.y = -minimum

static func measure(rig: Dictionary) -> Dictionary:
	var minimum: float = INF
	var maximum: float = -INF
	for part: int in Regions.PARTS.size():
		for point: Vector3 in rig.vertices[part]:
			var transformed: Vector3 = rig.meshes[part].global_transform * point
			if not transformed.is_finite():
				return {"valid":false, "reason":"nonfinite actual source geometry"}
			minimum = minf(minimum, transformed.y)
			maximum = maxf(maximum, transformed.y)
	var worst_gap: float = 0.0
	for child: int in rig.witnesses:
		var parent: int = PARENTS[child]
		for point: Vector3 in rig.witnesses[child]:
			var a: Vector3 = rig.meshes[parent].global_transform * point
			var b: Vector3 = rig.meshes[child].global_transform * point
			var gap: float = a.distance_to(b)
			worst_gap = maxf(worst_gap, gap)
	var closure: Dictionary = Closure.measure(rig, rig.closures)
	var rack_error: float = 0.0
	for column: int in 4:
		if column < 3:
			rack_error = maxf(rack_error, rig.meshes[13].global_transform.basis[column].distance_to(rig.meshes[16].global_transform.basis[column]))
		else:
			rack_error = maxf(rack_error, rig.meshes[13].global_position.distance_to(rig.meshes[16].global_position))
	return {"valid":true, "original_floor_y":minimum, "original_top_y":maximum, "maximum_original_seam_gap_m":worst_gap, "closure_covers_original_boundary_edges":closure.complete, "maximum_cap_to_original_rim_error_m":closure.maximum_cap_to_original_rim_error_m, "maximum_common_joint_center_error_m":closure.maximum_common_joint_center_error_m, "shared_parent_rack_transform_error":rack_error}

static func rest_error(rig: Dictionary) -> float:
	var maximum: float = 0.0
	var inverse: Transform3D = rig.root.global_transform.affine_inverse()
	for part: int in Regions.PARTS.size():
		for point: Vector3 in rig.vertices[part]:
			maximum = maxf(maximum, (inverse * rig.meshes[part].global_transform * point).distance_to(point))
	return maximum

static func _load(path: String) -> Node3D:
	var document: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	if document.append_from_file(path, state) != OK:
		return null
	return document.generate_scene(state)

static func _boundary_witnesses(raw: Dictionary, faces: Array[PackedInt32Array]) -> Dictionary:
	var primitive: Dictionary = raw.document.meshes[0].primitives[0]
	var positions: Dictionary = Access.accessor(raw.document, int(primitive.attributes.POSITION), 5126, "VEC3", RawAudit.VERTICES)
	var indices: Dictionary = Access.accessor(raw.document, int(primitive.indices), 5123, "SCALAR", RawAudit.TRIANGLES * 3)
	var owners: Dictionary[Vector3i, Dictionary] = {}
	var points: Dictionary[Vector3i, Vector3] = {}
	for part: int in faces.size():
		for face: int in faces[part]:
			for corner: int in 3:
				var vertex: int = raw.binary.decode_u16(int(indices.offset) + (face * 3 + corner) * int(indices.stride))
				var at: int = int(positions.offset) + vertex * int(positions.stride)
				var point: Vector3 = Vector3(raw.binary.decode_float(at), raw.binary.decode_float(at + 4), raw.binary.decode_float(at + 8))
				var cell: Vector3i = Vector3i((point * 1000000.0).round())
				if not owners.has(cell):
					owners[cell] = {}
					points[cell] = point
				owners[cell][part] = true
	var witnesses: Dictionary[int, PackedVector3Array] = {}
	for child: int in Regions.PARTS.size():
		var parent: int = PARENTS[child]
		if parent < 0 or child == 16:
			continue
		witnesses[child] = PackedVector3Array()
		for cell: Vector3i in owners:
			if owners[cell].has(child) and owners[cell].has(parent):
				witnesses[child].append(points[cell])
	return witnesses
