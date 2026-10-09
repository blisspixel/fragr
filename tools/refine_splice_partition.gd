extends SceneTree

## Rest-frame regions only. Actual source joints remain a separate motion gate.
const GlbData = preload("res://../tools/tern_glb.gd")
const Access = preload("res://../tools/edda_skin_repair.gd")
const RawAudit = preload("res://../tools/audit_splice_source.gd")
const PARTS: PackedStringArray = ["head", "neck", "torso", "pelvis", "left_upper_arm", "left_forearm", "left_hand", "right_upper_arm", "right_forearm", "right_hand", "left_upper_leg", "left_lower_leg", "left_foot", "right_upper_leg", "right_lower_leg", "right_foot", "right_rack_and_stored_tools"]
const COLORS: PackedStringArray = ["d8b061", "786ab5", "67a0bc", "d6b497", "bc6b4b", "ef9b4a", "f6d784", "7aa97a", "4bbfaf", "80e1bf", "ab7cbe", "745ba8", "b5a1e5", "d589a3", "ad596f", "f7bdd0", "df8053"]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1 or not args[0].is_absolute_path() or FileAccess.get_sha256(RawAudit.SOURCE) != RawAudit.SHA:
		_fail("pinned original and fresh absolute output required")
		return
	var directory: String = args[0]
	if FileAccess.file_exists(directory.path_join("labels.glb")) or DirAccess.make_dir_recursive_absolute(directory) != OK:
		_fail("refuse prior candidate overwrite")
		return
	var raw: Dictionary = GlbData.read(RawAudit.SOURCE)
	var original: Dictionary = raw.document.meshes[0].primitives[0]
	var position: Dictionary = Access.accessor(raw.document, int(original.attributes.POSITION), 5126, "VEC3", RawAudit.VERTICES)
	var indices: Dictionary = Access.accessor(raw.document, int(original.indices), 5123, "SCALAR", RawAudit.TRIANGLES * 3)
	if position.is_empty() or indices.is_empty():
		_fail("unexpected original accessors")
		return
	var points: PackedVector3Array = []
	for vertex: int in RawAudit.VERTICES:
		var at: int = int(position.offset) + vertex * int(position.stride)
		points.append(Vector3(raw.binary.decode_float(at), raw.binary.decode_float(at + 4), raw.binary.decode_float(at + 8)))
	var faces: Array[PackedInt32Array] = []
	var assignments: PackedInt32Array = []
	for _part: String in PARTS:
		faces.append(PackedInt32Array())
	for triangle: int in RawAudit.TRIANGLES:
		var center: Vector3 = Vector3.ZERO
		for corner: int in 3:
			center += points[raw.binary.decode_u16(int(indices.offset) + (triangle * 3 + corner) * int(indices.stride))]
		var part: int = proposed_part(center / 3.0)
		assignments.append(part)
	var cleanup: Dictionary = reassign_disconnected_regions(raw, assignments, points)
	assignments = cleanup.assignments
	for triangle: int in RawAudit.TRIANGLES:
		faces[assignments[triangle]].append(triangle)
	var output: Dictionary = build(raw, faces)
	if output.is_empty() or not GlbData.write(directory.path_join("labels.glb"), output.document, output.binary):
		_fail("candidate could not be written")
		return
	output = GlbData.read(directory.path_join("labels.glb"))
	var positive: bool = verify_coverage(raw, output, faces)
	var identity: bool = verify_identity(raw, faces)
	var controls: Dictionary = negative_controls(raw, output, faces)
	var boundaries: Dictionary = measure_boundaries(raw, assignments, points)
	var components: Array[Dictionary] = region_components(raw, assignments, points)
	var rows: Array[Dictionary] = []
	for part: int in PARTS.size():
		rows.append({"part":PARTS[part], "original_triangles":faces[part].size(), "original_triangle_ids":Array(faces[part]), "added_closure_triangles":0})
	var report: Dictionary = {"schema":1, "source_sha256":RawAudit.SHA, "diagnostic_sha256":FileAccess.get_sha256(directory.path_join("labels.glb")), "original_triangles":RawAudit.TRIANGLES, "added_closure_triangles":0, "exact_original_triangle_coverage":positive, "anatomical_region_identity":identity, "negative_controls":controls, "rows":rows, "boundaries":boundaries, "components":components, "disconnected_reassignments":cleanup.moves, "status":"unaccepted geometry-guided rest regions; no pivots, closures or motion"}
	var file: FileAccess = FileAccess.open(directory.path_join("partition.json"), FileAccess.WRITE)
	if file == null:
		_fail("cannot retain complete geometry receipt")
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	if not positive or not identity or false in controls.values() or FileAccess.get_sha256(RawAudit.SOURCE) != RawAudit.SHA:
		_fail("exact source coverage or negative control failed")
		return
	print("refine_splice_partition: PASS (exact rest geometry, seven negative controls; moving source remains unaccepted)")
	quit(0)

static func proposed_part(center: Vector3) -> int:
	if center.y > 0.735:
		return 0
	if center.y > 0.67 and absf(center.x + 0.01) < 0.095:
		return 1
	# The actual elbows lie inboard of the previous 0.245 m cutoff. Below
	# their shoulder attachments there is a measured empty lateral corridor.
	var separator: float = 0.205 if center.y > 0.50 else 0.18
	if center.y < 0.25:
		separator = minf(0.18 + (0.25 - center.y) * 0.75, 0.25 if center.x > 0.0 else 0.29)
	if absf(center.x) > separator and center.y > -0.34:
		var left: bool = center.x > 0.0
		if center.y > 0.31:
			return 4 if left else 7
		if center.y > -0.025:
			return 5 if left else 8
		return 6 if left else 9
	if center.y > 0.28:
		return 2
	if center.y > 0.105 or (center.y > 0.025 and absf(center.x - 0.02) < 0.055):
		return 3
	# This outboard hip attachment shares its parent transform with the right
	# upper leg. Tools remain stored; separate grip/socket acceptance is open.
	if center.x < -0.225 and center.y > -0.31 and center.y < 0.055 and center.z > -0.005:
		return 16
	var left: bool = center.x > 0.02
	if center.y > -0.34:
		return 10 if left else 13
	if center.y > -0.77:
		return 11 if left else 14
	return 12 if left else 15

static func build(raw: Dictionary, faces: Array[PackedInt32Array]) -> Dictionary:
	var doc: Dictionary = raw.document.duplicate(true)
	var binary: PackedByteArray = raw.binary.duplicate()
	var primitive: Dictionary = doc.meshes[0].primitives[0]
	var old_indices: Dictionary = Access.accessor(doc, int(primitive.indices), 5123, "SCALAR", RawAudit.TRIANGLES * 3)
	var meshes: Array[Dictionary] = []
	var nodes: Array[Dictionary] = []
	var roots: Array[int] = []
	for part: int in PARTS.size():
		if faces[part].is_empty():
			return {}
		while binary.size() % 4 != 0:
			binary.append(0)
		var start: int = binary.size()
		var data: PackedByteArray = []
		data.resize(faces[part].size() * 6)
		for face: int in faces[part].size():
			for corner: int in 3:
				data.encode_u16((face * 3 + corner) * 2, raw.binary.decode_u16(int(old_indices.offset) + (faces[part][face] * 3 + corner) * int(old_indices.stride)))
		binary.append_array(data)
		var view: int = doc.bufferViews.size()
		doc.bufferViews.append({"buffer":0, "byteOffset":start, "byteLength":data.size(), "target":34963})
		var accessor: int = doc.accessors.size()
		doc.accessors.append({"bufferView":view, "byteOffset":0, "componentType":5123, "count":faces[part].size() * 3, "type":"SCALAR"})
		var color: Color = Color(COLORS[part])
		var material: int = doc.materials.size()
		doc.materials.append({"name":PARTS[part], "pbrMetallicRoughness":{"baseColorFactor":[color.r, color.g, color.b, 1], "metallicFactor":0, "roughnessFactor":1}, "doubleSided":true})
		meshes.append({"name":PARTS[part], "primitives":[{"attributes":primitive.attributes.duplicate(true), "indices":accessor, "material":material, "mode":4}]})
		nodes.append({"name":PARTS[part], "mesh":part})
		roots.append(part)
	doc.meshes = meshes
	doc.nodes = nodes
	doc.scenes = [{"name":"MeasuredRestRegions", "nodes":roots}]
	doc.scene = 0
	doc.buffers[0].byteLength = binary.size()
	doc.asset.erase("generator")
	return {"document":doc, "binary":binary}

static func verify_coverage(raw: Dictionary, output: Dictionary, faces: Array[PackedInt32Array]) -> bool:
	if output.is_empty() or output.document.meshes.size() != PARTS.size() or output.document.nodes.size() != PARTS.size():
		return false
	var original: Dictionary = raw.document.meshes[0].primitives[0]
	var old_indices: Dictionary = Access.accessor(raw.document, int(original.indices), 5123, "SCALAR", RawAudit.TRIANGLES * 3)
	var seen: Dictionary[int, bool] = {}
	for part: int in PARTS.size():
		var node: Dictionary = output.document.nodes[part]
		if node.size() != 2 or node.get("name") != PARTS[part] or int(node.get("mesh", -1)) != part:
			return false
		var primitive: Dictionary = output.document.meshes[part].primitives[0]
		if primitive.attributes != original.attributes:
			return false
		var new_indices: Dictionary = Access.accessor(output.document, int(primitive.indices), 5123, "SCALAR", faces[part].size() * 3)
		if new_indices.is_empty():
			return false
		for face: int in faces[part].size():
			var id: int = faces[part][face]
			if id < 0 or id >= RawAudit.TRIANGLES or seen.has(id):
				return false
			seen[id] = true
			for corner: int in 3:
				if output.binary.decode_u16(int(new_indices.offset) + (face * 3 + corner) * 2) != raw.binary.decode_u16(int(old_indices.offset) + (id * 3 + corner) * int(old_indices.stride)):
					return false
	for attribute: String in original.attributes:
		var accessor: int = int(original.attributes[attribute])
		if raw.document.accessors[accessor] != output.document.accessors[accessor]:
			return false
		var view: int = int(raw.document.accessors[accessor].bufferView)
		if raw.document.bufferViews[view] != output.document.bufferViews[view]:
			return false
		var definition: Dictionary = raw.document.bufferViews[view]
		var start: int = int(definition.get("byteOffset", 0))
		if raw.binary.slice(start, start + int(definition.byteLength)) != output.binary.slice(start, start + int(definition.byteLength)):
			return false
	return seen.size() == RawAudit.TRIANGLES

static func negative_controls(raw: Dictionary, output: Dictionary, faces: Array[PackedInt32Array]) -> Dictionary:
	var controls: Dictionary = {}
	for kind: String in ["normal", "uv", "winding", "duplicate_triangle", "omitted_triangle", "displaced_part", "wrong_anatomical_side"]:
		var altered: Dictionary = output.duplicate(true)
		altered.binary = output.binary.duplicate()
		var changed_faces: Array[PackedInt32Array] = []
		for part: PackedInt32Array in faces:
			changed_faces.append(part.duplicate())
		if kind in ["normal", "uv"]:
			var attribute: String = "NORMAL" if kind == "normal" else "TEXCOORD_0"
			var accessor: int = int(altered.document.meshes[0].primitives[0].attributes[attribute])
			var view: int = int(altered.document.accessors[accessor].bufferView)
			altered.binary[int(altered.document.bufferViews[view].get("byteOffset", 0))] ^= 1
		elif kind == "winding":
			var accessor: int = int(altered.document.meshes[0].primitives[0].indices)
			var at: int = int(altered.document.bufferViews[int(altered.document.accessors[accessor].bufferView)].byteOffset)
			var a: int = altered.binary.decode_u16(at)
			altered.binary.encode_u16(at, altered.binary.decode_u16(at + 2))
			altered.binary.encode_u16(at + 2, a)
		elif kind == "duplicate_triangle":
			changed_faces[1][0] = changed_faces[0][0]
			var old_indices: Dictionary = Access.accessor(raw.document, int(raw.document.meshes[0].primitives[0].indices), 5123, "SCALAR", RawAudit.TRIANGLES * 3)
			var accessor: int = int(altered.document.meshes[1].primitives[0].indices)
			var at: int = int(altered.document.bufferViews[int(altered.document.accessors[accessor].bufferView)].byteOffset)
			for corner: int in 3:
				altered.binary.encode_u16(at + corner * 2, raw.binary.decode_u16(int(old_indices.offset) + (changed_faces[0][0] * 3 + corner) * int(old_indices.stride)))
		elif kind == "omitted_triangle":
			changed_faces[-1].resize(changed_faces[-1].size() - 1)
			altered.document.accessors[int(altered.document.meshes[-1].primitives[0].indices)].count -= 3
		elif kind == "wrong_anatomical_side":
			# Swap actual source surfaces while preserving every original triangle,
			# all part names and rest transforms. Coverage alone must still pass.
			var left: PackedInt32Array = changed_faces[4]
			changed_faces[4] = changed_faces[7]
			changed_faces[7] = left
			altered = build(raw, changed_faces)
		else:
			altered.document.nodes[0]["translation"] = [1, 0, 0]
		if kind == "wrong_anatomical_side":
			controls[kind] = verify_coverage(raw, altered, changed_faces) and not verify_identity(raw, changed_faces)
		else:
			controls[kind] = not verify_coverage(raw, altered, changed_faces)
	return controls

static func verify_identity(raw: Dictionary, faces: Array[PackedInt32Array]) -> bool:
	var primitive: Dictionary = raw.document.meshes[0].primitives[0]
	var positions: Dictionary = Access.accessor(raw.document, int(primitive.attributes.POSITION), 5126, "VEC3", RawAudit.VERTICES)
	var indices: Dictionary = Access.accessor(raw.document, int(primitive.indices), 5123, "SCALAR", RawAudit.TRIANGLES * 3)
	for part: int in [4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]:
		if faces[part].is_empty():
			return false
		var x_sum: float = 0.0
		for face: int in faces[part]:
			for corner: int in 3:
				var vertex: int = raw.binary.decode_u16(int(indices.offset) + (face * 3 + corner) * int(indices.stride))
				x_sum += raw.binary.decode_float(int(positions.offset) + vertex * int(positions.stride))
		var mean_x: float = x_sum / (faces[part].size() * 3)
		if (part in [4, 5, 6, 10, 11, 12] and mean_x < 0.05) or (part in [7, 8, 9, 13, 14, 15, 16] and mean_x > -0.05):
			return false
	return true

static func measure_boundaries(raw: Dictionary, assignments: PackedInt32Array, points: PackedVector3Array) -> Dictionary:
	var mapping: PackedInt32Array = []
	var groups: Dictionary[Vector3i, int] = {}
	var representatives: PackedVector3Array = []
	for point: Vector3 in points:
		var key: Vector3i = Vector3i((point * 1000000.0).round())
		if not groups.has(key):
			groups[key] = representatives.size()
			representatives.append(point)
		mapping.append(groups[key])
	var indices: Dictionary = Access.accessor(raw.document, int(raw.document.meshes[0].primitives[0].indices), 5123, "SCALAR", RawAudit.TRIANGLES * 3)
	var edges: Dictionary[Vector2i, Dictionary] = {}
	for triangle: int in RawAudit.TRIANGLES:
		var ids: PackedInt32Array = []
		for corner: int in 3:
			ids.append(mapping[raw.binary.decode_u16(int(indices.offset) + (triangle * 3 + corner) * int(indices.stride))])
		for corner: int in 3:
			var key: Vector2i = Vector2i(mini(ids[corner], ids[(corner + 1) % 3]), maxi(ids[corner], ids[(corner + 1) % 3]))
			if not edges.has(key):
				edges[key] = {"faces":[], "parts":[]}
			edges[key].faces.append(triangle)
			if not assignments[triangle] in edges[key].parts:
				edges[key].parts.append(assignments[triangle])
	var allowed: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3), Vector2i(2, 4), Vector2i(4, 5), Vector2i(5, 6), Vector2i(2, 7), Vector2i(7, 8), Vector2i(8, 9), Vector2i(3, 10), Vector2i(10, 11), Vector2i(11, 12), Vector2i(3, 13), Vector2i(13, 14), Vector2i(14, 15), Vector2i(13, 16)]
	var pairs: Dictionary[String, Dictionary] = {}
	var open_edges: int = 0
	var nonmanifold: int = 0
	var cuts: int = 0
	var unwanted: int = 0
	for edge_key: Vector2i in edges:
		var edge: Dictionary = edges[edge_key]
		open_edges += int(edge.faces.size() == 1)
		nonmanifold += int(edge.faces.size() > 2)
		if edge.parts.size() < 2:
			continue
		cuts += 1
		edge.parts.sort()
		var names: PackedStringArray = []
		for part: int in edge.parts:
			names.append(PARTS[part])
		var pair: String = "|".join(names)
		var valid: bool = edge.parts.size() == 2 and Vector2i(edge.parts[0], edge.parts[1]) in allowed
		unwanted += int(not valid)
		if not pairs.has(pair):
			pairs[pair] = {"edge_count":0, "points":[], "total_edge_length_m":0.0, "allowed_parent_child":valid}
		pairs[pair].edge_count += 1
		pairs[pair].points.append(representatives[edge_key.x])
		pairs[pair].points.append(representatives[edge_key.y])
		pairs[pair].total_edge_length_m += representatives[edge_key.x].distance_to(representatives[edge_key.y])
	var rows: Array[Dictionary] = []
	for pair: String in pairs:
		var item: Dictionary = pairs[pair]
		var bounds: AABB = AABB(item.points[0], Vector3.ZERO)
		var sum: Vector3 = Vector3.ZERO
		for point: Vector3 in item.points:
			bounds = bounds.expand(point)
			sum += point
		var mean: Vector3 = sum / item.points.size()
		var radius: float = 0.0
		for point: Vector3 in item.points:
			radius = maxf(radius, point.distance_to(mean))
		rows.append({"parts":pair.split("|"), "cut_edges":item.edge_count, "allowed_parent_child":item.allowed_parent_child, "total_edge_length_m":item.total_edge_length_m, "edge_end_mean":[mean.x, mean.y, mean.z], "maximum_boundary_radius_m":radius, "bounds_min":[bounds.position.x, bounds.position.y, bounds.position.z], "bounds_max":[bounds.end.x, bounds.end.y, bounds.end.z]})
	return {"scope":"actual welded region interfaces; no accepted joint, pivot or closure", "weld_tolerance_m":0.000001, "original_unique_edges":edges.size(), "original_open_edges":open_edges, "original_nonmanifold_edges":nonmanifold, "cross_part_cut_edges":cuts, "unwanted_parent_interfaces":unwanted, "interfaces":rows}

static func region_components(raw: Dictionary, assignments: PackedInt32Array, points: PackedVector3Array) -> Array[Dictionary]:
	return _component_geometry(raw, assignments, points).rows

static func _component_geometry(raw: Dictionary, assignments: PackedInt32Array, points: PackedVector3Array) -> Dictionary:
	var indices: Dictionary = Access.accessor(raw.document, int(raw.document.meshes[0].primitives[0].indices), 5123, "SCALAR", RawAudit.TRIANGLES * 3)
	var parents: PackedInt32Array = []
	for triangle: int in RawAudit.TRIANGLES:
		parents.append(triangle)
	var touches: Dictionary[String, int] = {}
	for triangle: int in RawAudit.TRIANGLES:
		for corner: int in 3:
			var point: Vector3 = points[raw.binary.decode_u16(int(indices.offset) + (triangle * 3 + corner) * int(indices.stride))]
			var cell: Vector3i = Vector3i((point * 1000000.0).round())
			var key: String = "%d:%d:%d:%d" % [assignments[triangle], cell.x, cell.y, cell.z]
			if touches.has(key):
				RawAudit._join(parents, triangle, touches[key])
			else:
				touches[key] = triangle
	var counts: Array[Dictionary] = []
	var roots: PackedInt32Array = []
	for _part: String in PARTS:
		counts.append({})
	for triangle: int in RawAudit.TRIANGLES:
		var id: int = RawAudit._find(parents, triangle)
		roots.append(id)
		var part: int = assignments[triangle]
		counts[part][id] = int(counts[part].get(id, 0)) + 1
	var rows: Array[Dictionary] = []
	for part: int in PARTS.size():
		var sizes: Array = counts[part].values()
		sizes.sort()
		sizes.reverse()
		rows.append({"part":PARTS[part], "vertex_connected_components":sizes.size(), "original_triangle_counts":sizes})
	return {"rows":rows, "counts":counts, "roots":roots}

static func reassign_disconnected_regions(raw: Dictionary, input: PackedInt32Array, points: PackedVector3Array) -> Dictionary:
	var assignments: PackedInt32Array = input.duplicate()
	var indices: Dictionary = Access.accessor(raw.document, int(raw.document.meshes[0].primitives[0].indices), 5123, "SCALAR", RawAudit.TRIANGLES * 3)
	var touches: Dictionary[Vector3i, PackedInt32Array] = {}
	for triangle: int in RawAudit.TRIANGLES:
		for corner: int in 3:
			var point: Vector3 = points[raw.binary.decode_u16(int(indices.offset) + (triangle * 3 + corner) * int(indices.stride))]
			var cell: Vector3i = Vector3i((point * 1000000.0).round())
			if not touches.has(cell):
				touches[cell] = PackedInt32Array()
			touches[cell].append(triangle)
	var moves: Array[Dictionary] = []
	# Only transfer secondary connected surfaces through actual welded contact.
	# The holster/tools deliberately remain a shared-parent attachment region.
	for _pass: int in 3:
		var geometry: Dictionary = _component_geometry(raw, assignments, points)
		var mains: PackedInt32Array = []
		for counts: Dictionary in geometry.counts:
			var largest: int = -1
			for id: int in counts:
				if largest < 0 or counts[id] > counts[largest]:
					largest = id
			mains.append(largest)
		var secondary: Dictionary[int, PackedInt32Array] = {}
		for triangle: int in RawAudit.TRIANGLES:
			var part: int = assignments[triangle]
			var id: int = geometry.roots[triangle]
			if part == 16 or id == mains[part]:
				continue
			if not secondary.has(id):
				secondary[id] = PackedInt32Array()
			secondary[id].append(triangle)
		if secondary.is_empty():
			break
		var next: PackedInt32Array = assignments.duplicate()
		for id: int in secondary:
			var from: int = assignments[secondary[id][0]]
			var candidates: Dictionary[int, int] = {}
			for triangle: int in secondary[id]:
				for corner: int in 3:
					var point: Vector3 = points[raw.binary.decode_u16(int(indices.offset) + (triangle * 3 + corner) * int(indices.stride))]
					var cell: Vector3i = Vector3i((point * 1000000.0).round())
					for neighbor: int in touches[cell]:
						var to: int = assignments[neighbor]
						if to != from and to != 16 and geometry.roots[neighbor] == mains[to]:
							candidates[to] = int(candidates.get(to, 0)) + 1
			var winner: int = -1
			for to: int in candidates:
				if winner < 0 or candidates[to] > candidates[winner] or (candidates[to] == candidates[winner] and to < winner):
					winner = to
			if winner < 0:
				continue
			for triangle: int in secondary[id]:
				next[triangle] = winner
			moves.append({"pass":_pass, "from":PARTS[from], "to":PARTS[winner], "original_triangle_ids":Array(secondary[id]), "welded_contact_votes":candidates[winner]})
		assignments = next
	return {"assignments":assignments, "moves":moves}

func _fail(reason: String) -> void:
	push_error("refine_splice_partition: " + reason)
	quit(1)
