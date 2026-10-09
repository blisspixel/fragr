extends SceneTree

## Read-only source measurements. No partition or motion is accepted here.
const GlbData = preload("res://../tools/tern_glb.gd")
const Access = preload("res://../tools/edda_skin_repair.gd")
const SOURCE: String = "res://../art/raw/meshy-pilot-20261003/splice-named-v1-ultra-0.glb"
const SHA: String = "4560940190c9877b78885e3138c5e3628e9bfe906474ca14f54986931bbe19f1"
const VERTICES: int = 27283
const TRIANGLES: int = 16602

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1 or not args[0].is_absolute_path() or FileAccess.get_sha256(SOURCE) != SHA:
		push_error("audit_splice_source: pinned source and absolute fresh output required")
		quit(1)
		return
	var directory: String = args[0]
	if FileAccess.file_exists(directory.path_join("source.json")) or DirAccess.make_dir_recursive_absolute(directory) != OK:
		push_error("audit_splice_source: cannot overwrite prior measurements")
		quit(1)
		return
	var source: Dictionary = GlbData.read(SOURCE)
	if source.is_empty():
		quit(1)
		return
	var doc: Dictionary = source.document
	if doc.get("meshes", []).size() != 1 or doc.meshes[0].get("primitives", []).size() != 1 or not doc.get("skins", []).is_empty() or not doc.get("animations", []).is_empty():
		push_error("audit_splice_source: unexpected source shape")
		quit(1)
		return
	var primitive: Dictionary = doc.meshes[0].primitives[0]
	var position: Dictionary = Access.accessor(doc, int(primitive.attributes.POSITION), 5126, "VEC3", VERTICES)
	var normals: Dictionary = Access.accessor(doc, int(primitive.attributes.NORMAL), 5126, "VEC3", VERTICES)
	var uv: Dictionary = Access.accessor(doc, int(primitive.attributes.TEXCOORD_0), 5126, "VEC2", VERTICES)
	var indices: Dictionary = Access.accessor(doc, int(primitive.indices), 5123, "SCALAR", TRIANGLES * 3)
	for descriptor: Dictionary in [position, normals, uv, indices]:
		if descriptor.is_empty() or int(descriptor.end) > source.binary.size():
			push_error("audit_splice_source: unexpected or truncated accessor")
			quit(1)
			return
	var base: Dictionary = doc.materials[int(primitive.material)].pbrMetallicRoughness.baseColorTexture
	var image_definition: Dictionary = doc.images[int(doc.textures[int(base.index)].source)]
	var image_view: Dictionary = doc.bufferViews[int(image_definition.bufferView)]
	var image_bytes: PackedByteArray = source.binary.slice(int(image_view.get("byteOffset", 0)), int(image_view.get("byteOffset", 0)) + int(image_view.byteLength))
	var image: Image = Image.new()
	var image_error: Error = image.load_jpg_from_buffer(image_bytes) if image_definition.mimeType == "image/jpeg" else image.load_png_from_buffer(image_bytes)
	if image_error != OK:
		push_error("audit_splice_source: actual original paint cannot decode")
		quit(1)
		return
	var points: PackedVector3Array = []
	var directions: PackedVector3Array = []
	var texels: PackedVector2Array = []
	var parents: PackedInt32Array = []
	var welded: PackedInt32Array = []
	var coincident: Dictionary[Vector3i, int] = {}
	var first: bool = true
	var bounds: AABB = AABB()
	for vertex: int in range(VERTICES):
		var point: Vector3 = _vector3(source.binary, int(position.offset) + vertex * int(position.stride))
		var normal: Vector3 = _vector3(source.binary, int(normals.offset) + vertex * int(normals.stride))
		var offset: int = int(uv.offset) + vertex * int(uv.stride)
		var coordinate: Vector2 = Vector2(source.binary.decode_float(offset), source.binary.decode_float(offset + 4))
		if not point.is_finite() or not normal.is_finite() or not coordinate.is_finite():
			push_error("audit_splice_source: nonfinite original attribute")
			quit(1)
			return
		points.append(point)
		directions.append(normal)
		texels.append(coordinate)
		parents.append(vertex)
		welded.append(vertex)
		var key: Vector3i = Vector3i((point * 1000000.0).round())
		if coincident.has(key):
			_join(welded, vertex, coincident[key])
		else:
			coincident[key] = vertex
		bounds = AABB(point, Vector3.ZERO) if first else bounds.expand(point)
		first = false
	var csv: FileAccess = FileAccess.open(directory.path_join("original-triangles.csv"), FileAccess.WRITE)
	if csv == null:
		quit(1)
		return
	csv.store_csv_line(["triangle", "a", "b", "c", "x", "y", "z", "normal_x", "normal_y", "normal_z", "u", "v", "r", "g", "b_color", "area", "uv_area"])
	var degenerate: int = 0
	var uv_degenerate: int = 0
	var normal_disagreement: int = 0
	var left_rust: Array[Vector3] = []
	var right_rust: Array[Vector3] = []
	var left_magenta: Array[Vector3] = []
	var right_magenta: Array[Vector3] = []
	for triangle: int in range(TRIANGLES):
		var ids: PackedInt32Array = []
		for corner: int in range(3):
			var id: int = source.binary.decode_u16(int(indices.offset) + (triangle * 3 + corner) * int(indices.stride))
			if id >= VERTICES:
				push_error("audit_splice_source: invalid original index")
				csv.close()
				quit(1)
				return
			ids.append(id)
		_join(parents, ids[0], ids[1])
		_join(parents, ids[0], ids[2])
		_join(welded, ids[0], ids[1])
		_join(welded, ids[0], ids[2])
		var center: Vector3 = (points[ids[0]] + points[ids[1]] + points[ids[2]]) / 3.0
		var cross: Vector3 = (points[ids[1]] - points[ids[0]]).cross(points[ids[2]] - points[ids[0]])
		var area: float = cross.length() * 0.5
		var texture_area: float = absf((texels[ids[1]] - texels[ids[0]]).cross(texels[ids[2]] - texels[ids[0]])) * 0.5
		degenerate += int(area <= 1e-12)
		uv_degenerate += int(texture_area <= 1e-12)
		normal_disagreement += int(cross.dot(directions[ids[0]] + directions[ids[1]] + directions[ids[2]]) <= 0.0)
		var coordinate: Vector2 = (texels[ids[0]] + texels[ids[1]] + texels[ids[2]]) / 3.0
		var color: Color = image.get_pixel(clampi(int(coordinate.x * image.get_width()), 0, image.get_width()-1), clampi(int(coordinate.y * image.get_height()), 0, image.get_height()-1))
		# Color counts are diagnostic hints inside actual lateral forearm space,
		# never a rigid partition or an anatomical-side acceptance by themselves.
		if absf(center.x) > 0.25 and center.y > -0.48 and center.y < 0.10:
			if color.r > 0.15 and color.r > color.g * 1.3 and color.g > color.b * 1.2:
				(left_rust if center.x > 0.0 else right_rust).append(center)
			if color.r > color.g * 1.5 and color.b > color.g * 1.3 and color.r > 0.1:
				(left_magenta if center.x > 0.0 else right_magenta).append(center)
		var direction: Vector3 = cross.normalized()
		csv.store_csv_line([str(triangle),str(ids[0]),str(ids[1]),str(ids[2]),str(center.x),str(center.y),str(center.z),str(direction.x),str(direction.y),str(direction.z),str(coordinate.x),str(coordinate.y),str(color.r),str(color.g),str(color.b),str(area),str(texture_area)])
	csv.close()
	var original_components: Dictionary = {}
	var welded_components: Dictionary = {}
	for vertex: int in range(VERTICES):
		original_components[_find(parents, vertex)] = true
		welded_components[_find(welded, vertex)] = true
	var report: Dictionary = {"schema":1,"source":"art/raw/meshy-pilot-20261003/splice-named-v1-ultra-0.glb","sha256":SHA,"vertices":VERTICES,"triangles":TRIANGLES,"skins":0,"animations":0,"bounds_min":[bounds.position.x,bounds.position.y,bounds.position.z],"bounds_max":[bounds.end.x,bounds.end.y,bounds.end.z],"indexed_components":original_components.size(),"coincident_1e6_components":welded_components.size(),"coincident_position_groups":coincident.size(),"geometry_degenerate_1e12":degenerate,"uv_degenerate_1e12":uv_degenerate,"normal_disagreement":normal_disagreement,"actual_paint_dimensions":[image.get_width(),image.get_height()],"forearm_color_hints":{"positive_x_rust":left_rust.size(),"negative_x_rust":right_rust.size(),"positive_x_magenta":left_magenta.size(),"negative_x_magenta":right_magenta.size()},"triangle_csv_sha256":FileAccess.get_sha256(directory.path_join("original-triangles.csv")),"acceptance":"read-only measurements; no pivots, parts, pose or runtime selected"}
	var file: FileAccess = FileAccess.open(directory.path_join("source.json"),FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(JSON.stringify(report,"\t")+"\n")
	file.close()
	if FileAccess.get_sha256(SOURCE) != SHA:
		push_error("audit_splice_source: source changed during read")
		quit(1)
		return
	print("audit_splice_source: PASS (pinned original attributes, complete triangle measurements, read-only paint and connectivity)")
	quit(0)

static func _vector3(bytes: PackedByteArray, offset: int) -> Vector3:
	return Vector3(bytes.decode_float(offset),bytes.decode_float(offset+4),bytes.decode_float(offset+8))

static func _find(parents: PackedInt32Array, vertex: int) -> int:
	while parents[vertex] != vertex:
		parents[vertex] = parents[parents[vertex]]
		vertex = parents[vertex]
	return vertex

static func _join(parents: PackedInt32Array, a: int, b: int) -> void:
	var x: int = _find(parents,a)
	var y: int = _find(parents,b)
	if x != y:
		parents[y] = x
