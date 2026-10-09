extends RefCounted

## Offline reload helper. Uses the exported artifact's nodes, meshes and clips.
const SourceRig = preload("res://../tools/splice_mechanical_rig.gd")

static func load_candidate(regions: String, prepared: String, expected_sha: String) -> Dictionary:
	if FileAccess.get_sha256(prepared) != expected_sha:
		return {}
	var reference: Dictionary = SourceRig.build(regions, "f2191a008a44537b821b80da5bdf181958f69890bf6b9d388a51e1d75ebeb7a8")
	if reference.is_empty():
		return {}
	var model: Node3D = SourceRig._load(prepared)
	if model == null:
		reference.root.free()
		return {}
	var prepared_root: Node3D = model.find_child("SplicePrepared", true, false) as Node3D
	var players: Array[Node] = model.find_children("*", "AnimationPlayer", true, false)
	if prepared_root == null or players.size() != 1:
		model.free()
		reference.root.free()
		return {}
	var player: AnimationPlayer = players[0] as AnimationPlayer
	if not player.has_animation("calm") or not player.has_animation("walk"):
		model.free()
		reference.root.free()
		return {}
	var parts: Array[Node3D] = []
	var meshes: Array[MeshInstance3D] = []
	var vertices: Array[PackedVector3Array] = []
	for part: String in SourceRig.Regions.PARTS:
		var pivot: Node3D = model.find_child(part, true, false) as Node3D
		var mesh: MeshInstance3D = model.find_child(part + "_surface", true, false) as MeshInstance3D
		if pivot == null or mesh == null:
			model.free()
			reference.root.free()
			return {}
		parts.append(pivot)
		meshes.append(mesh)
		var arrays: Array = mesh.mesh.surface_get_arrays(0)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var used: Dictionary[int, bool] = {}
		var measured: PackedVector3Array = []
		for index: int in indices:
			if not used.has(index):
				used[index] = true
				measured.append(points[index])
		vertices.append(measured)
	var closures: Dictionary[int, Array] = {}
	for child: int in reference.closures:
		var pair: Array = []
		for cap: Dictionary in reference.closures[child]:
			var node: MeshInstance3D = model.find_child(String(cap.node.name), true, false) as MeshInstance3D
			if node == null:
				model.free()
				reference.root.free()
				return {}
			pair.append({"node":node,"owner":cap.owner,"original_points":cap.original_points,"center":cap.center})
		closures[child] = pair
	return {"model":model,"reference":reference,"root":prepared_root,"parts":parts,"meshes":meshes,"vertices":vertices,"closures":closures,"witnesses":reference.witnesses,"player":player,"prepared_sha256":expected_sha}

static func sample(candidate: Dictionary, clip: String, phase: float) -> void:
	var player: AnimationPlayer = candidate.player
	player.play(clip)
	player.seek(clampf(phase,0.0,1.0) * player.get_animation(clip).length, true)
	player.advance(0.0)
	player.pause()

static func maximum_source_difference(candidate: Dictionary) -> float:
	var maximum: float = 0.0
	var source: Dictionary = candidate.reference
	for part: int in SourceRig.Regions.PARTS.size():
		if candidate.vertices[part].size() != source.vertices[part].size():
			return INF
		for index: int in candidate.vertices[part].size():
			var prepared_point: Vector3 = candidate.meshes[part].global_transform * candidate.vertices[part][index]
			var source_point: Vector3 = source.meshes[part].global_transform * source.vertices[part][index]
			maximum = maxf(maximum, prepared_point.distance_to(source_point))
	return maximum

static func actual_cap_meshes_match(candidate: Dictionary) -> bool:
	var geometry: Dictionary = native_cap_geometry(candidate)
	return geometry.valid and float(geometry.maximum_local_position_error_m) <= 0.00001

static func native_cap_geometry(candidate: Dictionary) -> Dictionary:
	var rows: Array[Dictionary] = []
	var maximum: float = 0.0
	var permutations: Array[PackedInt32Array] = [PackedInt32Array([0,1,2]),PackedInt32Array([0,2,1]),PackedInt32Array([1,0,2]),PackedInt32Array([1,2,0]),PackedInt32Array([2,0,1]),PackedInt32Array([2,1,0])]
	for child: int in candidate.closures:
		for index: int in candidate.closures[child].size():
			var imported: MeshInstance3D = candidate.closures[child][index].node
			var reference: MeshInstance3D = candidate.reference.closures[child][index].node
			if imported.mesh.get_surface_count() != 1 or reference.mesh.get_surface_count() != 1:
				return {"valid":false,"maximum_local_position_error_m":INF}
			var a: PackedVector3Array = _triangle_points(imported.mesh.surface_get_arrays(0))
			var b: PackedVector3Array = _triangle_points(reference.mesh.surface_get_arrays(0))
			if a.size() != b.size() or a.size() % 3 != 0:
				return {"valid":false,"maximum_local_position_error_m":INF}
			var original_points: PackedVector3Array = []
			for face: int in a.size() / 3:
				var best: float = INF
				var chosen: PackedInt32Array = []
				for permutation: PackedInt32Array in permutations:
					var error: float = 0.0
					for corner: int in 3:
						error = maxf(error,a[face*3+corner].distance_to(b[face*3+permutation[corner]]))
					if error < best:
						best = error
						chosen = permutation
				maximum = maxf(maximum,best)
				if chosen.is_empty():
					return {"valid":false,"maximum_local_position_error_m":INF}
				for corner: int in 3:
					original_points.append(b[face*3+chosen[corner]])
			rows.append({"node":imported,"child":child,"owner":candidate.closures[child][index].owner,"center":candidate.closures[child][index].center,"original_points":original_points,"actual_points":a})
	return {"valid":true,"maximum_local_position_error_m":maximum,"rows":rows}

static func measure_native_caps(candidate: Dictionary, geometry: Dictionary) -> Dictionary:
	var maximum_rim: float = 0.0
	var centers: Dictionary[int,PackedVector3Array] = {}
	var center_error: float = 0.0
	for row: Dictionary in geometry.rows:
		var found_center: bool = false
		for index: int in row.actual_points.size():
			var expected: Vector3 = row.original_points[index]
			var actual: Vector3 = row.node.global_transform * row.actual_points[index]
			if expected.distance_to(row.center) < 0.00000001:
				if not found_center:
					if not centers.has(int(row.child)):
						centers[int(row.child)] = PackedVector3Array()
					centers[int(row.child)].append(actual)
					found_center = true
			else:
				var source: Vector3 = candidate.meshes[int(row.owner)].global_transform * expected
				maximum_rim = maxf(maximum_rim,actual.distance_to(source))
	for child: int in centers:
		if centers[child].size() != 2:
			return {"valid":false,"rim_error_m":INF,"center_error_m":INF}
		center_error = maxf(center_error,centers[child][0].distance_to(centers[child][1]))
	return {"valid":centers.size() == candidate.closures.size(),"rim_error_m":maximum_rim,"center_error_m":center_error}

static func _triangle_points(arrays: Array) -> PackedVector3Array:
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var output: PackedVector3Array = []
	if indices.is_empty():
		return points
	for index: int in indices:
		output.append(points[index])
	return output

static func _triangle_cells(arrays: Array) -> Dictionary:
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var count: int = indices.size() if not indices.is_empty() else points.size()
	var faces: Dictionary[String,int] = {}
	for face: int in count / 3:
		var corners: PackedStringArray = []
		for corner: int in 3:
			var vertex: int = indices[face*3+corner] if not indices.is_empty() else face*3+corner
			var point: Vector3 = points[vertex]
			if not point.is_finite():
				return {"invalid":-1}
			var cell: Vector3i = Vector3i((point*1000000.0).round())
			corners.append("%d,%d,%d" % [cell.x,cell.y,cell.z])
		corners.sort()
		var key: String = ";".join(corners)
		faces[key] = int(faces.get(key,0)) + 1
	return faces
