extends SceneTree

const Glb = preload("res://../tools/tern_glb.gd")
const Source = preload("res://art/models/edda_source.gd")
const SOURCE_SHA: String = "bb5511f280147bb3f4fa81db6ce1b42a58cb10daebdf486def6a807d3286693f"
var _failures: PackedStringArray = []

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 3 or FileAccess.get_sha256(args[0]) != SOURCE_SHA:
		_fail("require pinned original, prepared source and report")
		return
	var original: Dictionary = Glb.read(args[0])
	var prepared: Dictionary = Glb.read(args[1])
	if original.is_empty() or prepared.is_empty():
		_fail("invalid container")
		return
	_expect(_preserved(original, prepared), "all geometry/UV/bind/animation payloads and legal metadata preserved")
	var skin: Dictionary = _skin(original, prepared)
	_expect(skin.valid, "valid normalized skin and unchanged weights outside justified region")
	_expect(_witnesses(prepared), "actual fingertip, bilateral wrist and satchel influences repaired")
	var expected_material: Dictionary = original.document.materials[0].duplicate(true)
	expected_material.pbrMetallicRoughness.metallicFactor = 0.08
	expected_material.pbrMetallicRoughness.roughnessFactor = 1.0
	_expect(prepared.document.materials == [expected_material], "original material locations and double-sided state with only declared matte factors")
	var controls: Dictionary = {}
	for kind: String in ["uv", "winding", "unaffected_weight", "invalid_joint", "missing_repair"]:
		var altered: Dictionary = prepared.duplicate(true)
		var data: PackedByteArray = prepared.binary.duplicate()
		var accessor: int = {"uv": 2, "winding": 6, "unaffected_weight": 5, "invalid_joint": 4, "missing_repair": 5}[kind]
		var location: Dictionary = _accessor(altered, accessor)
		if kind == "missing_repair":
			for index: int in [4, 5]:
				var target: Dictionary = _accessor(altered, index)
				var input: Dictionary = _accessor(original, index)
				for vertex: int in range(17561):
					for byte: int in range(input.width):
						data[target.offset + vertex * target.stride + byte] = original.binary[input.offset + vertex * input.stride + byte]
		elif kind == "winding":
			for byte: int in range(location.width):
				var swap: int = data[location.offset + location.width + byte]
				data[location.offset + location.width + byte] = data[location.offset + location.width * 2 + byte]
				data[location.offset + location.width * 2 + byte] = swap
		elif kind == "invalid_joint":
			data[location.offset + 11225 * location.stride] = 255
		else:
			data.encode_float(location.offset, data.decode_float(location.offset) + 0.125)
		altered.binary = data
		var rejected: bool = not _preserved(original, altered) if kind in ["uv", "winding"] else (not _skin(original, altered).valid or not _witnesses(altered))
		controls[kind] = rejected
		_expect(rejected, kind + " negative control rejected")
	var maps: Array[Dictionary] = []
	for index: int in range(3):
		var image: Image = Image.new()
		var view: Dictionary = prepared.document.bufferViews[int(prepared.document.images[index].bufferView)]
		_expect(image.load_png_from_buffer(prepared.binary.slice(int(view.byteOffset), int(view.byteOffset) + int(view.byteLength))) == OK, "embedded PNG map decoded")
		_expect(image.get_size() == Vector2i(1024, 1024), "compact map size")
		var minimum_green: int = 255
		if index == 2:
			var pixels: PackedByteArray = image.get_data()
			for offset: int in range(1, pixels.size(), 3):
				minimum_green = mini(minimum_green, pixels[offset])
			_expect(minimum_green >= 224, "encoded matte floor")
		maps.append({"image": index, "width": image.get_width(), "height": image.get_height(), "minimum_green": minimum_green if index == 2 else null})
	var poses: Array[Dictionary] = []
	var source: RefCounted = Source.new()
	for action: String in ["rest", "calm", "walk", "crouch", "fallen"]:
		var count: int = 16 if action == "walk" else 1
		for sample: int in range(count):
			var phase: float = (sample + 0.37) / 16.0 if action == "walk" else (1.0 if action == "fallen" else 0.0)
			var figure: Node3D = source.build_pose(action, phase, true)
			root.add_child(figure)
			await process_frame
			var points: PackedVector3Array = Source.weighted_points(figure)
			_expect(points.size() == 17561, "complete actual weighted geometry " + action)
			if points.is_empty():
				figure.free()
				continue
			var bounds: AABB = AABB(points[0], Vector3.ZERO)
			for point: Vector3 in points:
				_expect(point.is_finite(), "finite weighted point")
				bounds = bounds.expand(point)
			_expect(absf(bounds.position.y) < 0.0001, "actual feet/fall geometry grounded " + action)
			if action == "rest":
				_expect(absf(bounds.size.y - 1.8) < 0.001, "1.8m retained source scale")
			var skeleton: Skeleton3D = figure.find_child("Skeleton3D", true, false) as Skeleton3D
			var joints: Dictionary = {}
			for name: String in ["LeftHand", "RightHand", "LeftForeArm", "RightForeArm", "LeftFoot", "RightFoot"]:
				var point: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(name)).origin
				joints[name] = [point.x, point.y, point.z]
			if action == "calm":
				for side: String in ["Left", "Right"]:
					var wrist: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(side + "Hand")).origin
					_expect(wrist.distance_to(Vector3(0.35 if side == "Left" else -0.27, 0.97, 0.08)) < 0.001, "actual resting wrist " + side)
			poses.append({"action": action, "phase": phase, "weighted_min_y": bounds.position.y, "weighted_height": bounds.size.y,
				"weighted_size": [bounds.size.x, bounds.size.y, bounds.size.z], "joints_world": joints})
			figure.free()
	await process_frame
	var file: FileAccess = FileAccess.open(args[2], FileAccess.WRITE)
	if file == null:
		_fail("report write failed")
		return
	file.store_string(JSON.stringify({"schema": 1, "source_sha256": SOURCE_SHA, "candidate_sha256": FileAccess.get_sha256(args[1]),
		"runtime_selected": false, "preserved_payloads": _preserved(original, prepared), "skin": skin, "negative_controls": controls,
		"maps": maps, "poses": poses, "external_hand_contact_verified": false, "failures": _failures}, "\t") + "\n")
	file.close()
	if not _failures.is_empty():
		_fail("; ".join(_failures))
		return
	print("validate_edda_source: PASS (payload/skin preservation, five negative controls, 20 weighted pose controls)")
	quit(0)

func _preserved(a: Dictionary, b: Dictionary) -> bool:
	for key: String in ["accessors", "meshes", "nodes", "skins", "animations", "scenes", "scene", "textures", "samplers"]:
		if a.document.get(key) != b.document.get(key):
			return false
	if a.document.asset.get("copyright", "") != b.document.asset.get("copyright", "") or b.document.asset.has("generator"):
		return false
	var av: Array = a.document.bufferViews
	var bv: Array = b.document.bufferViews
	if av.size() != bv.size():
		return false
	var excluded: Array[int] = [int(a.document.accessors[4].bufferView), int(a.document.accessors[5].bufferView)]
	for image: Dictionary in a.document.images:
		excluded.append(int(image.bufferView))
	for index: int in range(av.size()):
		var contract_a: Dictionary = av[index].duplicate()
		var contract_b: Dictionary = bv[index].duplicate()
		for key: String in ["byteOffset", "byteLength"]:
			contract_a.erase(key)
			contract_b.erase(key)
		if contract_a != contract_b:
			return false
		if index in excluded:
			continue
		var offset_a: int = int(av[index].get("byteOffset", 0))
		var offset_b: int = int(bv[index].get("byteOffset", 0))
		if av[index].byteLength != bv[index].byteLength or a.binary.slice(offset_a, offset_a + int(av[index].byteLength)) != b.binary.slice(offset_b, offset_b + int(bv[index].byteLength)):
			return false
	return true

func _skin(a: Dictionary, b: Dictionary) -> Dictionary:
	var original_j: Dictionary = _accessor(a, 4)
	var original_w: Dictionary = _accessor(a, 5)
	var joints: Dictionary = _accessor(b, 4)
	var weights: Dictionary = _accessor(b, 5)
	var position: Dictionary = _accessor(a, 0)
	var valid: bool = true
	var changed: Array[int] = []
	var outside_changes: Array[int] = []
	var maximum_sum_error: float = 0.0
	for vertex: int in range(17561):
		var j: int = joints.offset + vertex * joints.stride
		var w: int = weights.offset + vertex * weights.stride
		var aj: int = original_j.offset + vertex * original_j.stride
		var aw: int = original_w.offset + vertex * original_w.stride
		var total: float = 0.0
		for influence: int in range(4):
			var weight: float = b.binary.decode_float(w + influence * 4)
			valid = valid and b.binary[j + influence] < 24 and is_finite(weight) and weight >= 0.0 and weight <= 1.0
			total += weight
		maximum_sum_error = maxf(maximum_sum_error, absf(total - 1.0))
		if a.binary.slice(aj, aj + 4) == b.binary.slice(j, j + 4) and a.binary.slice(aw, aw + 16) == b.binary.slice(w, w + 16):
			continue
		changed.append(vertex)
		var p: int = position.offset + vertex * position.stride
		var x: float = a.binary.decode_float(p)
		var y: float = a.binary.decode_float(p + 4)
		# Independent conservative bounds for the inspected bag, diagonal strap,
		# apron transition and bilateral forearm repair. Other skin stays exact.
		var allowed: bool = (x > 0.05 and x < 0.36 and y > 0.70 and y < 1.30) or (absf(x) > 0.23 and y > 0.70 and y < 1.15) or (absf(x) < 0.25 and y >= 1.04 and y < 1.46)
		if not allowed:
			outside_changes.append(vertex)
	valid = valid and maximum_sum_error < 0.000001 and outside_changes.is_empty() and not changed.is_empty()
	return {"valid": valid, "changed_vertices": changed, "changed_count": changed.size(), "unchanged_count": 17561 - changed.size(),
		"outside_changes": outside_changes, "maximum_weight_sum_error": maximum_sum_error}

func _witnesses(value: Dictionary) -> bool:
	var joints: Dictionary = _accessor(value, 4)
	var weights: Dictionary = _accessor(value, 5)
	for vertex: int in [11225, 11226, 8133, 8168, 10970, 12116, 12117]:
		var total: float = 0.0
		for influence: int in range(4):
			var joint: int = value.binary[joints.offset + vertex * joints.stride + influence]
			if joint >= 24:
				return false
			var name: String = value.document.nodes[int(value.document.skins[0].joints[joint])].name
			var weight: float = value.binary.decode_float(weights.offset + vertex * weights.stride + influence * 4)
			if vertex in [12116, 12117]:
				if name == "Hips":
					total += weight
			elif name.ends_with("Hand") or name.ends_with("ForeArm"):
				total += weight
		if total < 0.999:
			return false
	return true

func _accessor(value: Dictionary, index: int) -> Dictionary:
	var accessor: Dictionary = value.document.accessors[index]
	var view: Dictionary = value.document.bufferViews[int(accessor.bufferView)]
	var width: int = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[accessor.type] * {5121: 1, 5123: 2, 5126: 4}[int(accessor.componentType)]
	return {"offset": int(view.get("byteOffset", 0)) + int(accessor.get("byteOffset", 0)), "stride": int(view.get("byteStride", width)), "width": width}

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _fail(message: String) -> void:
	push_error("validate_edda_source: " + message)
	quit(1)
