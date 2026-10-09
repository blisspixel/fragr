extends SceneTree

## Original-triangle labels only. Unresolved joints/rack prevent pose acceptance.
const GlbData = preload("res://../tools/tern_glb.gd")
const Access = preload("res://../tools/edda_skin_repair.gd")
const RawAudit = preload("res://../tools/audit_splice_source.gd")
const PARTS: PackedStringArray = ["head", "neck", "torso", "pelvis", "left_upper_arm", "left_forearm", "left_hand", "right_upper_arm", "right_forearm", "right_hand", "left_upper_leg", "left_lower_leg", "left_foot", "right_upper_leg_and_unresolved_rack", "right_lower_leg", "right_foot"]
const COLORS: PackedStringArray = ["d8b061", "786ab5", "67a0bc", "d6b497", "bc6b4b", "ef9b4a", "f6d784", "7aa97a", "4bbfaf", "80e1bf", "ab7cbe", "745ba8", "b5a1e5", "d589a3", "ad596f", "f7bdd0"]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1 or not args[0].is_absolute_path() or FileAccess.get_sha256(RawAudit.SOURCE) != RawAudit.SHA:
		push_error("partition_splice_diagnostic: absolute fresh output and pinned source required")
		quit(1)
		return
	var directory: String = args[0]
	if FileAccess.file_exists(directory.path_join("labels.glb")) or DirAccess.make_dir_recursive_absolute(directory) != OK:
		push_error("partition_splice_diagnostic: refuse prior diagnostic overwrite")
		quit(1)
		return
	var raw: Dictionary = GlbData.read(RawAudit.SOURCE)
	var doc: Dictionary = raw.document.duplicate(true)
	if doc.nodes.size() != 1 or doc.nodes[0].size() != 2 or doc.nodes[0].mesh != 0 or doc.meshes.size() != 1:
		push_error("partition_splice_diagnostic: unexpected original rest transform")
		quit(1)
		return
	var primitive: Dictionary = doc.meshes[0].primitives[0]
	var position: Dictionary = Access.accessor(doc, int(primitive.attributes.POSITION), 5126, "VEC3", RawAudit.VERTICES)
	var indices: Dictionary = Access.accessor(doc, int(primitive.indices), 5123, "SCALAR", RawAudit.TRIANGLES * 3)
	if position.is_empty() or indices.is_empty():
		quit(1)
		return
	var points: PackedVector3Array = []
	for vertex: int in range(RawAudit.VERTICES):
		var start: int = int(position.offset) + vertex * int(position.stride)
		points.append(Vector3(raw.binary.decode_float(start),raw.binary.decode_float(start+4),raw.binary.decode_float(start+8)))
	var part_indices: Array[PackedInt32Array] = []
	var face_ids: Array[PackedInt32Array] = []
	var assignments: PackedInt32Array = []
	for _part: String in PARTS:
		part_indices.append(PackedInt32Array())
		face_ids.append(PackedInt32Array())
	for triangle: int in range(RawAudit.TRIANGLES):
		var face: PackedInt32Array = []
		for corner: int in range(3):
			face.append(raw.binary.decode_u16(int(indices.offset) + (triangle * 3 + corner) * int(indices.stride)))
		var center: Vector3 = (points[face[0]] + points[face[1]] + points[face[2]]) / 3.0
		var part: int = proposed_part(center)
		assignments.append(part)
		part_indices[part].append_array(face)
		face_ids[part].append(triangle)
	var binary: PackedByteArray = raw.binary.duplicate()
	var new_meshes: Array[Dictionary] = []
	var new_nodes: Array[Dictionary] = []
	var roots: Array[int] = []
	var rows: Array[Dictionary] = []
	for part: int in range(PARTS.size()):
		if part_indices[part].is_empty():
			push_error("partition_splice_diagnostic: empty measured label " + PARTS[part])
			quit(1)
			return
		while binary.size() % 4 != 0:
			binary.append(0)
		var start: int = binary.size()
		var data: PackedByteArray = []
		data.resize(part_indices[part].size() * 2)
		for index: int in range(part_indices[part].size()):
			data.encode_u16(index * 2, part_indices[part][index])
		binary.append_array(data)
		var view: int = doc.bufferViews.size()
		doc.bufferViews.append({"buffer":0, "byteOffset":start, "byteLength":data.size(), "target":34963})
		var accessor: int = doc.accessors.size()
		doc.accessors.append({"bufferView":view, "byteOffset":0, "componentType":5123, "count":part_indices[part].size(), "type":"SCALAR"})
		var color: Color = Color(COLORS[part])
		var material: int = doc.materials.size()
		doc.materials.append({"name":PARTS[part], "pbrMetallicRoughness":{"baseColorFactor":[color.r,color.g,color.b,1], "metallicFactor":0, "roughnessFactor":1}, "doubleSided":true})
		new_meshes.append({"name":PARTS[part], "primitives":[{"attributes":primitive.attributes.duplicate(true), "indices":accessor, "material":material, "mode":4}]})
		new_nodes.append({"name":PARTS[part], "mesh":part})
		roots.append(part)
		rows.append({"part":PARTS[part], "original_triangle_ids":Array(face_ids[part]), "original_triangles":face_ids[part].size(), "added_closure_triangles":0})
	doc.meshes = new_meshes
	doc.nodes = new_nodes
	doc.scenes = [{"name":"OriginalTriangleLabels", "nodes":roots}]
	doc.scene = 0
	doc.buffers[0].byteLength = binary.size()
	doc.asset.erase("generator")
	# Changing structural members is intentional for this diagnostic. Existing
	# accessor and all original attribute buffer payloads remain verbatim.
	if not GlbData.write(directory.path_join("labels.glb"),doc,binary):
		quit(1)
		return
	var output: Dictionary = GlbData.read(directory.path_join("labels.glb"))
	var exact: bool = verify_coverage(raw, output, face_ids)
	var controls: Dictionary = negative_controls(raw, output, face_ids)
	var boundaries: Dictionary = measure_boundaries(raw,assignments,points)
	var report: Dictionary = {"schema":1, "source_sha256":RawAudit.SHA, "diagnostic_sha256":FileAccess.get_sha256(directory.path_join("labels.glb")), "exact_original_triangle_coverage":exact, "negative_controls":controls, "original_triangles":RawAudit.TRIANGLES, "added_closure_triangles":0, "rows":rows, "boundaries":boundaries, "status":"unaccepted source labels, no pivots or motion; right rack unresolved"}
	var file: FileAccess = FileAccess.open(directory.path_join("partition.json"),FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(JSON.stringify(report,"\t")+"\n")
	file.close()
	if not exact or false in controls.values() or FileAccess.get_sha256(RawAudit.SOURCE) != RawAudit.SHA:
		push_error("partition_splice_diagnostic: source coverage failure")
		quit(1)
		return
	print("partition_splice_diagnostic: PASS exact original triangle/attribute coverage; labels remain unaccepted")
	quit(0)

static func proposed_part(center: Vector3) -> int:
	if center.y > 0.735:
		return 0
	if center.y > 0.635 and absf(center.x) < 0.13:
		return 1
	if absf(center.x) > 0.245 and center.y > -0.26:
		var left: bool = center.x > 0.0
		if center.y > 0.31:
			return 4 if left else 7
		if center.y > -0.025:
			return 5 if left else 8
		return 6 if left else 9
	if center.y > 0.28:
		return 2
	if center.y > 0.105:
		return 3
	var left: bool = center.x > 0.0
	if center.y > -0.34:
		return 10 if left else 13
	if center.y > -0.77:
		return 11 if left else 14
	return 12 if left else 15

static func verify_coverage(raw: Dictionary, output: Dictionary, faces: Array[PackedInt32Array]) -> bool:
	if output.is_empty() or output.document.meshes.size() != PARTS.size() or output.document.nodes.size() != PARTS.size():
		return false
	var original: Dictionary = raw.document.meshes[0].primitives[0]
	var old_indices: Dictionary = Access.accessor(raw.document, int(original.indices), 5123, "SCALAR", RawAudit.TRIANGLES * 3)
	var seen: Dictionary[int,bool] = {}
	for part: int in range(PARTS.size()):
		var node: Dictionary = output.document.nodes[part]
		if node.size() != 2 or node.get("name") != PARTS[part] or int(node.get("mesh", -1)) != part:
			return false
		var primitive: Dictionary = output.document.meshes[part].primitives[0]
		if primitive.attributes != original.attributes:
			return false
		var new_indices: Dictionary = Access.accessor(output.document, int(primitive.indices), 5123, "SCALAR", faces[part].size() * 3)
		if new_indices.is_empty():
			return false
		for face: int in range(faces[part].size()):
			var id: int = faces[part][face]
			if seen.has(id):
				return false
			seen[id] = true
			for corner: int in range(3):
				if output.binary.decode_u16(int(new_indices.offset)+(face*3+corner)*2) != raw.binary.decode_u16(int(old_indices.offset)+(id*3+corner)*int(old_indices.stride)):
					return false
	for attribute: String in original.attributes:
		var accessor: int = int(original.attributes[attribute])
		if raw.document.accessors[accessor] != output.document.accessors[accessor]:
			return false
		var view: int = int(raw.document.accessors[accessor].bufferView)
		if raw.document.bufferViews[view] != output.document.bufferViews[view]:
			return false
		var definition: Dictionary = raw.document.bufferViews[view]
		var start: int = int(definition.get("byteOffset",0))
		var end: int = start + int(definition.byteLength)
		if raw.binary.slice(start,end) != output.binary.slice(start,end):
			return false
	return seen.size() == RawAudit.TRIANGLES

static func negative_controls(raw: Dictionary, output: Dictionary, faces: Array[PackedInt32Array]) -> Dictionary:
	var controls: Dictionary = {}
	for kind: String in ["normal", "uv", "winding", "duplicate_triangle", "omitted_triangle", "displaced_part"]:
		var altered: Dictionary = output.duplicate(true)
		altered.binary = output.binary.duplicate()
		var changed_faces: Array[PackedInt32Array] = []
		for part: PackedInt32Array in faces:
			changed_faces.append(part.duplicate())
		if kind in ["normal", "uv"]:
			var attribute: String = "NORMAL" if kind == "normal" else "TEXCOORD_0"
			var accessor: int = int(altered.document.meshes[0].primitives[0].attributes[attribute])
			var view: int = int(altered.document.accessors[accessor].bufferView)
			var at: int = int(altered.document.bufferViews[view].get("byteOffset",0))
			altered.binary[at] ^= 1
		elif kind == "winding":
			var accessor: int = int(altered.document.meshes[0].primitives[0].indices)
			var at: int = int(altered.document.bufferViews[int(altered.document.accessors[accessor].bufferView)].byteOffset)
			var original: int = altered.binary.decode_u16(at)
			altered.binary.encode_u16(at, altered.binary.decode_u16(at+2))
			altered.binary.encode_u16(at+2, original)
		elif kind == "duplicate_triangle":
			changed_faces[1][0] = changed_faces[0][0]
			var old_accessor: Dictionary = Access.accessor(raw.document, int(raw.document.meshes[0].primitives[0].indices),5123,"SCALAR",RawAudit.TRIANGLES*3)
			var accessor: int = int(altered.document.meshes[1].primitives[0].indices)
			var at: int = int(altered.document.bufferViews[int(altered.document.accessors[accessor].bufferView)].byteOffset)
			for corner: int in range(3):
				altered.binary.encode_u16(at+corner*2,raw.binary.decode_u16(int(old_accessor.offset)+(changed_faces[0][0]*3+corner)*int(old_accessor.stride)))
		elif kind == "omitted_triangle":
			changed_faces[-1].resize(changed_faces[-1].size()-1)
			altered.document.accessors[int(altered.document.meshes[-1].primitives[0].indices)].count -= 3
		else:
			altered.document.nodes[0]["translation"] = [1,0,0]
		controls[kind] = not verify_coverage(raw,altered,changed_faces)
	return controls

static func measure_boundaries(raw: Dictionary, assignments: PackedInt32Array, points: PackedVector3Array) -> Dictionary:
	var groups: Dictionary[Vector3i,int] = {}
	var mapping: PackedInt32Array = []
	var representatives: PackedVector3Array = []
	for point: Vector3 in points:
		var key: Vector3i = Vector3i((point*1000000.0).round())
		if not groups.has(key):
			groups[key] = representatives.size()
			representatives.append(point)
		mapping.append(groups[key])
	var descriptor: Dictionary = Access.accessor(raw.document,int(raw.document.meshes[0].primitives[0].indices),5123,"SCALAR",RawAudit.TRIANGLES*3)
	var edges: Dictionary[Vector2i,Dictionary] = {}
	for triangle: int in range(RawAudit.TRIANGLES):
		var ids: PackedInt32Array = []
		for corner: int in range(3):
			ids.append(mapping[raw.binary.decode_u16(int(descriptor.offset)+(triangle*3+corner)*int(descriptor.stride))])
		for corner: int in range(3):
			var a: int = ids[corner]
			var b: int = ids[(corner+1)%3]
			var key: Vector2i = Vector2i(mini(a,b),maxi(a,b))
			if not edges.has(key):
				edges[key] = {"faces":[],"parts":[]}
			edges[key].faces.append(triangle)
			if not assignments[triangle] in edges[key].parts:
				edges[key].parts.append(assignments[triangle])
	var open_edges: int = 0
	var nonmanifold: int = 0
	var cut_edges: int = 0
	var pairs: Dictionary[String,Dictionary] = {}
	for key: Vector2i in edges:
		var edge: Dictionary = edges[key]
		open_edges += int(edge.faces.size() == 1)
		nonmanifold += int(edge.faces.size() > 2)
		if edge.parts.size() < 2:
			continue
		cut_edges += 1
		edge.parts.sort()
		var names: PackedStringArray = []
		for part: int in edge.parts:
			names.append(PARTS[part])
		var pair: String = "|".join(names)
		if not pairs.has(pair):
			pairs[pair] = {"edge_count":0,"points":[],"total_edge_length_m":0.0}
		pairs[pair].edge_count += 1
		pairs[pair].points.append(representatives[key.x])
		pairs[pair].points.append(representatives[key.y])
		pairs[pair].total_edge_length_m += representatives[key.x].distance_to(representatives[key.y])
	var rows: Array[Dictionary] = []
	for pair: String in pairs:
		var item: Dictionary = pairs[pair]
		var bounds: AABB = AABB(item.points[0],Vector3.ZERO)
		var sum: Vector3 = Vector3.ZERO
		for point: Vector3 in item.points:
			bounds = bounds.expand(point)
			sum += point
		var mean: Vector3 = sum / item.points.size()
		rows.append({"parts":pair.split("|"),"cut_edges":item.edge_count,"total_edge_length_m":item.total_edge_length_m,"edge_end_mean":[mean.x,mean.y,mean.z],"bounds_min":[bounds.position.x,bounds.position.y,bounds.position.z],"bounds_max":[bounds.end.x,bounds.end.y,bounds.end.z]})
	return {"weld_tolerance_m":0.000001,"original_unique_edges":edges.size(),"original_open_edges":open_edges,"original_nonmanifold_edges":nonmanifold,"cross_part_cut_edges":cut_edges,"interfaces":rows,"scope":"actual original welded interfaces, unaccepted joint proposals; mean is not an accepted pivot"}
