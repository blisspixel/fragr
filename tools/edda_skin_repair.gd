extends RefCounted

const WALK_SHA256: String = "bb5511f280147bb3f4fa81db6ce1b42a58cb10daebdf486def6a807d3286693f"
const VERTICES: int = 17561
const TRIANGLES: int = 14694

# Pinned-source seed hints. Complete welded geometry and motion checks own acceptance.
# Anatomical left is positive X in this retained walking import.
static func region(point: Vector3, paint: Color) -> String:
	if point.x > 0.3 and point.y > 0.73 and point.y < 1.015 and absf(point.z) < 0.075:
		return "left_hand"
	var leather: bool = paint.r > paint.g * 1.08 and paint.g > paint.b * 1.08 and paint.r < 0.57
	var attachment: bool = leather or (paint.s < 0.14 and paint.v > 0.3)
	if point.x > 0.145 and point.x < 0.3 and point.y > 0.795 and point.y < 1.11 \
		and (leather or (point.x > 0.235 and attachment)):
		return "satchel"
	if leather and point.y >= 1.04 and point.y < 1.46 and absf(point.x) < 0.23:
		return "strap"
	return "original"

static func read(path: String) -> Dictionary:
	if FileAccess.get_sha256(path) != WALK_SHA256:
		return {}
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.size() < 28 or bytes.size() > 64 * 1024 * 1024 \
		or bytes.decode_u32(0) != 0x46546c67 or bytes.decode_u32(4) != 2 \
		or bytes.decode_u32(8) != bytes.size() or bytes.decode_u32(16) != 0x4e4f534a:
		return {}
	var length: int = bytes.decode_u32(12)
	if length % 4 != 0 or length > bytes.size() - 28:
		return {}
	var parsed: Variant = JSON.parse_string(bytes.slice(20, 20 + length).get_string_from_utf8())
	if not parsed is Dictionary or not parsed.get("meshes") is Array \
		or parsed["meshes"].size() != 1 or not parsed.get("skins") is Array \
		or parsed["skins"].size() != 1 or not parsed.get("accessors") is Array \
		or not parsed.get("bufferViews") is Array or not parsed.get("nodes") is Array:
		return {}
	var bin_start: int = 28 + length
	if bytes.decode_u32(24 + length) != 0x004e4942 \
		or bytes.decode_u32(20 + length) != bytes.size() - bin_start:
		return {}
	var primitive: Dictionary = parsed["meshes"][0]["primitives"][0]
	var attributes: Dictionary = primitive["attributes"]
	var position: Dictionary = accessor(parsed, int(attributes["POSITION"]), 5126, "VEC3", VERTICES)
	var uv: Dictionary = accessor(parsed, int(attributes["TEXCOORD_0"]), 5126, "VEC2", VERTICES)
	var joints: Dictionary = accessor(parsed, int(attributes["JOINTS_0"]), 5121, "VEC4", VERTICES)
	var weights: Dictionary = accessor(parsed, int(attributes["WEIGHTS_0"]), 5126, "VEC4", VERTICES)
	var indices: Dictionary = accessor(parsed, int(primitive["indices"]), 5123, "SCALAR", TRIANGLES * 3)
	for item: Dictionary in [position, uv, joints, weights, indices]:
		if item.is_empty() or int(item["end"]) > bytes.size() - bin_start:
			return {}
	var hip: int = -1
	var chest: int = -1
	var left_hand: int = -1
	var left_forearm: int = -1
	var skin_joints: Array = parsed["skins"][0]["joints"]
	if skin_joints.size() != 24:
		return {}
	for bind: int in range(skin_joints.size()):
		var name: String = str(parsed["nodes"][int(skin_joints[bind])].get("name", ""))
		if name == "Hips":
			hip = bind
		elif name == "Spine":
			chest = bind
		elif name == "LeftHand":
			left_hand = bind
		elif name == "LeftForeArm":
			left_forearm = bind
	if hip < 0 or chest < 0 or left_hand < 0 or left_forearm < 0:
		return {}
	return {"bytes": bytes, "document": parsed, "bin_start": bin_start,
		"position": position, "uv": uv, "joints": joints, "weights": weights, "indices": indices,
		"hip": hip, "chest": chest, "left_hand": left_hand, "left_forearm": left_forearm}

static func accessor(document: Dictionary, index: int, component: int, type: String, count: int) -> Dictionary:
	if index < 0 or index >= document["accessors"].size():
		return {}
	var value: Variant = document["accessors"][index]
	if not value is Dictionary or int(value.get("componentType", -1)) != component \
		or value.get("type") != type or int(value.get("count", -1)) != count \
		or value.has("sparse") or not value.has("bufferView"):
		return {}
	var view_index: int = int(value["bufferView"])
	if view_index < 0 or view_index >= document["bufferViews"].size():
		return {}
	var view: Variant = document["bufferViews"][view_index]
	if not view is Dictionary or int(view.get("buffer", -1)) != 0:
		return {}
	var width: int = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}.get(type, 0)
	var size: int = {5121: 1, 5123: 2, 5126: 4}.get(component, 0)
	var stride: int = int(view.get("byteStride", width * size))
	var offset: int = int(view.get("byteOffset", 0)) + int(value.get("byteOffset", 0))
	var end: int = offset + (count - 1) * stride + width * size
	if width == 0 or size == 0 or stride < width * size or offset < 0 \
		or end > int(view.get("byteOffset", 0)) + int(view.get("byteLength", 0)):
		return {}
	return {"offset": offset, "stride": stride, "end": end}

static func point(source: Dictionary, vertex: int) -> Vector3:
	var bytes: PackedByteArray = source["bytes"]
	var start: int = int(source["bin_start"]) + int(source["position"]["offset"]) + vertex * int(source["position"]["stride"])
	return Vector3(bytes.decode_float(start), bytes.decode_float(start + 4), bytes.decode_float(start + 8))

static func paint(source: Dictionary, vertex: int, image: Image) -> Color:
	var bytes: PackedByteArray = source["bytes"]
	var start: int = int(source["bin_start"]) + int(source["uv"]["offset"]) + vertex * int(source["uv"]["stride"])
	var uv: Vector2 = Vector2(bytes.decode_float(start), bytes.decode_float(start + 4))
	return image.get_pixel(clampi(int(uv.x * image.get_width()), 0, image.get_width() - 1),
		clampi(int(uv.y * image.get_height()), 0, image.get_height() - 1))

static func corrected_bytes(source: Dictionary, image: Image) -> Dictionary:
	if source.is_empty() or image == null or image.is_empty():
		return {}
	var regions: Array[String] = labels(source, image)
	var input: PackedByteArray = source.bytes
	var ids: Dictionary[Vector3i, int] = {}
	var mapping: PackedInt32Array = []
	var groups: Array[PackedInt32Array] = []
	var points: PackedVector3Array = []
	var neighbors: Array[Dictionary] = []
	for vertex: int in range(VERTICES):
		var position: Vector3 = point(source, vertex)
		var key: Vector3i = Vector3i(roundi(position.x * 1000000), roundi(position.y * 1000000), roundi(position.z * 1000000))
		if not ids.has(key):
			ids[key] = groups.size()
			groups.append(PackedInt32Array())
			points.append(position)
			neighbors.append({})
		mapping.append(ids[key])
		groups[ids[key]].append(vertex)
	var index_start: int = int(source.bin_start) + int(source.indices.offset)
	for face: int in range(0, TRIANGLES * 3, 3):
		for corner: int in range(3):
			var a: int = mapping[input.decode_u16(index_start + (face + corner) * int(source.indices.stride))]
			var b: int = mapping[input.decode_u16(index_start + (face + (corner + 1) % 3) * int(source.indices.stride))]
			if a != b:
				var weight: float = 1.0 / maxf(0.002, points[a].distance_to(points[b]))
				neighbors[a][b] = weight
				neighbors[b][a] = weight
	var binds: Dictionary[String, int] = {}
	for bind: int in range(24): binds[source.document.nodes[int(source.document.skins[0].joints[bind])].name] = bind
	var values: Array[PackedFloat32Array] = []
	var references: Array[PackedFloat32Array] = []
	var editable: PackedByteArray = []
	var free: PackedInt32Array = []
	for group: int in range(groups.size()):
		var point: Vector3 = points[group]
		var votes: Dictionary[String, int] = {}
		var original: PackedFloat32Array = []
		original.resize(24)
		for vertex: int in groups[group]:
			votes[regions[vertex]] = votes.get(regions[vertex], 0) + 1
			var j: int = int(source.bin_start) + int(source.joints.offset) + vertex * int(source.joints.stride)
			var w: int = int(source.bin_start) + int(source.weights.offset) + vertex * int(source.weights.stride)
			for influence: int in range(4): original[input[j + influence]] += input.decode_float(w + influence * 4) / groups[group].size()
		references.append(original.duplicate())
		var changed: bool = votes.size() > 1 or not votes.has("original") or (absf(point.x) > 0.23 and point.y < 1.15 and point.y > 0.70) or (point.x > 0.05 and point.x < 0.34 and point.y > 0.70 and point.y < 1.30)
		editable.append(1 if changed else 0)
		var seed: Dictionary[int, float] = {}
		var hand_distance: float = point.distance_to(Vector3(0.334, 0.947, -0.010))
		if votes.get("satchel", 0) > 0 and hand_distance > 0.105:
			seed[binds["Hips"]] = 1.0
		elif votes.get("strap", 0) > 0:
			var blend: float = 1.0 - smoothstep(1.045, 1.27, point.y)
			for joint: int in range(24): seed[joint] = original[joint] * (1.0 - blend)
			seed[binds["Hips"]] += blend
		elif (point.x > 0.285 or point.x < -0.245) and point.y < 1.08 and point.y > 0.7:
			var side: String = "Left" if point.x > 0 else "Right"
			var blend: float = 1.0 - smoothstep(0.965, 1.065, point.y)
			seed[binds[side + "Hand"]] = blend
			seed[binds[side + "ForeArm"]] = 1.0 - blend
		elif changed and absf(point.x) > 0.245 and point.y >= 1.08:
			seed[binds[("Left" if point.x > 0 else "Right") + "ForeArm"]] = 1.0
		if changed and not seed.is_empty():
			original.fill(0)
			for joint: int in seed: original[joint] = seed[joint]
		elif changed:
			free.append(group)
		values.append(original)
	for iteration: int in range(400):
		var next: Array[PackedFloat32Array] = values.duplicate()
		for group: int in free:
			var total: float = 0.0
			var value: PackedFloat32Array = []
			value.resize(24)
			for other: int in neighbors[group]:
				var factor: float = neighbors[group][other]
				total += factor
				var prior: PackedFloat32Array = values[other]
				for joint: int in range(24): value[joint] += prior[joint] * factor
			if total > 0:
				for joint: int in range(24): value[joint] /= total
				next[group] = value
		values = next
	var bytes: PackedByteArray = input.duplicate()
	var changed_vertices: PackedInt32Array = []
	for group: int in range(groups.size()):
		if editable[group] == 0: continue
		var value: PackedFloat32Array = values[group]
		var difference: float = 0.0
		for joint: int in range(24):
			difference = maxf(difference, absf(value[joint] - references[group][joint]))
		# Unchanged upper strap seeds and their original skin remain byte-exact.
		if difference < 0.000001:
			continue
		var order: Array[int] = []
		for joint: int in range(24): order.append(joint)
		order.sort_custom(func(a: int, b: int) -> bool: return value[a] > value[b])
		var total: float = 0.0
		for joint: int in order.slice(0, 4): total += value[joint]
		for vertex: int in groups[group]:
			var j: int = int(source.bin_start) + int(source.joints.offset) + vertex * int(source.joints.stride)
			var w: int = int(source.bin_start) + int(source.weights.offset) + vertex * int(source.weights.stride)
			for influence: int in range(4):
				bytes[j + influence] = order[influence]
				bytes.encode_float(w + influence * 4, value[order[influence]] / total)
			changed_vertices.append(vertex)
	return {"bytes": bytes, "edited_vertices": changed_vertices, "free_groups": free.size(), "welded_groups": groups.size()}

static func labels(source: Dictionary, image: Image) -> Array[String]:
	var parents: PackedInt32Array = PackedInt32Array()
	for vertex: int in range(VERTICES):
		parents.append(vertex)
	var bytes: PackedByteArray = source["bytes"]
	var start: int = int(source["bin_start"]) + int(source["indices"]["offset"])
	var stride: int = int(source["indices"]["stride"])
	for face: int in range(0, TRIANGLES * 3, 3):
		var a: int = bytes.decode_u16(start + face * stride)
		var b: int = bytes.decode_u16(start + (face + 1) * stride)
		var c: int = bytes.decode_u16(start + (face + 2) * stride)
		_join(parents, a, b)
		_join(parents, a, c)
	var islands: Dictionary[int, Dictionary] = {}
	for vertex: int in range(VERTICES):
		var id: int = _find(parents, vertex)
		if not islands.has(id):
			islands[id] = {"count": 0, "point": Vector3.ZERO, "paint": Color(0, 0, 0, 0)}
		islands[id]["count"] += 1
		islands[id]["point"] += point(source, vertex)
		islands[id]["paint"] += paint(source, vertex, image)
	var classified: Dictionary[int, String] = {}
	for id: int in islands:
		classified[id] = region(islands[id]["point"] / float(islands[id]["count"]),
			islands[id]["paint"] / float(islands[id]["count"]))
	var result: Array[String] = []
	for vertex: int in range(VERTICES):
		result.append(classified[_find(parents, vertex)])
	return result

static func _find(parents: PackedInt32Array, vertex: int) -> int:
	var current: int = vertex
	while parents[current] != current:
		current = parents[current]
	return current

static func _join(parents: PackedInt32Array, a: int, b: int) -> void:
	parents[_find(parents, b)] = _find(parents, a)
