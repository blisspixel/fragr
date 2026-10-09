extends SceneTree

const GlbContainer = preload("res://../tools/tern_glb.gd")
const Source = preload("res://art/models/tern_source.gd")
const SOURCE_SHA: String = "9c9b3a8af8fee7c5f3d3fe52254871a4a6e022ed5dd56cbfb1f9cb9e9096ef89"
var _failures: PackedStringArray = []

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 3 or FileAccess.get_sha256(args[0]) != SOURCE_SHA:
		_fail("require pinned original, candidate and output receipt")
		return
	var original: Dictionary = GlbContainer.read(args[0])
	var prepared: Dictionary = GlbContainer.read(args[1])
	_expect(not original.is_empty() and not prepared.is_empty(), "valid embedded containers")
	if original.is_empty() or prepared.is_empty():
		_fail("invalid container")
		return
	_expect(_preserved(original, prepared), "all non-image data and topology preserved")
	var controls: Dictionary = {}
	var primitive: Dictionary = prepared.document.meshes[0].primitives[0]
	for label: String in ["uv_shift", "winding", "skin_weight"]:
		var altered: Dictionary = prepared.duplicate(true)
		var binary: PackedByteArray = prepared.binary.duplicate()
		var accessor_index: int = int(primitive.indices if label == "winding" else primitive.attributes["TEXCOORD_0" if label == "uv_shift" else "WEIGHTS_0"])
		var accessor: Dictionary = altered.document.accessors[accessor_index]
		var view: Dictionary = altered.document.bufferViews[int(accessor.bufferView)]
		var offset: int = int(view.get("byteOffset", 0)) + int(accessor.get("byteOffset", 0))
		if label == "winding":
			var width: int = 2 if int(accessor.componentType) == 5123 else 4
			for byte: int in range(width):
				var swap: int = binary[offset + width + byte]
				binary[offset + width + byte] = binary[offset + width * 2 + byte]
				binary[offset + width * 2 + byte] = swap
		else:
			binary.encode_float(offset, binary.decode_float(offset) + 0.125)
		altered.binary = binary
		controls[label] = not _preserved(original, altered)
		_expect(controls[label], label + " negative control rejected")
	var source_model: Node3D = _load_model(args[0])
	var candidate_model: Node3D = _load_model(args[1])
	if source_model == null or candidate_model == null:
		_fail("cannot import source pair")
		return
	root.add_child(source_model)
	root.add_child(candidate_model)
	var source_arrays: Array = _mesh(source_model).mesh.surface_get_arrays(0)
	var candidate_arrays: Array = _mesh(candidate_model).mesh.surface_get_arrays(0)
	for channel: int in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS, Mesh.ARRAY_INDEX]:
		_expect(source_arrays[channel] == candidate_arrays[channel], "imported geometry channel %d unchanged" % channel)
	_expect(source_arrays[Mesh.ARRAY_VERTEX].size() == 19106, "19106 retained vertices")
	_expect(source_arrays[Mesh.ARRAY_INDEX].size() == 37368, "12456 retained triangles")
	var original_rest: Dictionary = _bounds(Source.weighted_points(source_model))
	var prepared_rest: Dictionary = _bounds(Source.weighted_points(candidate_model))
	_expect(original_rest == prepared_rest, "weighted rest unchanged")
	_expect(absf(float(prepared_rest.height) - 1.8) < 0.001 and absf(float(prepared_rest.min_y)) < 0.0001, "1.8m original grounded rest")
	var material: StandardMaterial3D = _mesh(candidate_model).get_active_material(0) as StandardMaterial3D
	_expect(material != null and material.normal_enabled, "retained normal map")
	var map_rows: Array[Dictionary] = []
	for index: int in range(prepared.document.images.size()):
		var spec: Dictionary = prepared.document.images[index]
		var view: Dictionary = prepared.document.bufferViews[int(spec.bufferView)]
		var image: Image = Image.new()
		_expect(image.load_png_from_buffer(prepared.binary.slice(int(view.byteOffset), int(view.byteOffset) + int(view.byteLength))) == OK, "map decoded")
		_expect(image.get_size() == Vector2i(1024, 1024), "bounded 1K map")
		var low_green: float = 1.0
		if index == 2:
			for y: int in range(1024):
				for x: int in range(1024):
					low_green = minf(low_green, image.get_pixel(x, y).g)
			_expect(low_green >= 0.875, "matte roughness floor survives encoding")
		map_rows.append({"image": index, "size": [image.get_width(), image.get_height()], "green_min": low_green if index == 2 else null})
	var samples: Array[Dictionary] = []
	var pose_source: RefCounted = Source.new()
	# The editor's scene importer may reorder vertices. Use the same retained
	# PackedScene ordering for both sides of deformation measurements.
	var rest_figure: Node3D = pose_source.build_pose("rest", 0.0, true)
	root.add_child(rest_figure)
	await process_frame
	var rest_points: PackedVector3Array = Source.weighted_points(rest_figure)
	var indices: PackedInt32Array = _mesh(rest_figure).mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	rest_figure.free()
	var source_player: AnimationPlayer = source_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var candidate_player: AnimationPlayer = candidate_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var clip: StringName = source_player.get_animation_list()[0]
	_expect(source_player.get_animation(clip).length == candidate_player.get_animation(clip).length, "walk duration unchanged")
	for phase: int in range(8):
		var progress: float = float(phase) / 8.0
		for player: AnimationPlayer in [source_player, candidate_player]:
			player.play(clip)
			player.pause()
			player.seek(progress * player.get_animation(clip).length, true)
		var original_points: PackedVector3Array = Source.weighted_points(source_model)
		var prepared_points: PackedVector3Array = Source.weighted_points(candidate_model)
		_expect(original_points == prepared_points and original_points.size() == 19106, "actual original clip weighted phase %d preserved" % phase)
		var figure: Node3D = pose_source.build_pose("walk", progress, true)
		root.add_child(figure)
		await process_frame
		var points: PackedVector3Array = Source.weighted_points(figure)
		var bounds: Dictionary = _bounds(points)
		_expect(points.size() == 19106 and absf(float(bounds.min_y)) < 0.0001, "actual offline feet registered phase %d" % phase)
		_expect(absf(float(bounds.height) - float(prepared_rest.height)) > 0.001, "walk phase %d is posed rather than a static rest mesh" % phase)
		var skeleton: Skeleton3D = figure.find_child("Skeleton3D", true, false) as Skeleton3D
		var hands: Dictionary = {}
		for name: String in ["LeftHand", "RightHand", "LeftFoot", "RightFoot"]:
			var point: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(name)).origin
			hands[name] = [point.x, point.y, point.z]
		samples.append({"phase": progress, "original": _bounds(original_points), "registered": bounds,
			"joints_world": hands, "skin_edges": _edge_stretch(rest_points, points, indices)})
		figure.free()
	var calm: Node3D = pose_source.build_pose("calm", 0.0, true)
	root.add_child(calm)
	await process_frame
	var calm_points: PackedVector3Array = Source.weighted_points(calm)
	var calm_bounds: Dictionary = _bounds(calm_points)
	_expect(absf(float(calm_bounds.min_y)) < 0.0001, "calm actual feet registered")
	_expect(float(calm_bounds.size[0]) < 0.75, "calm hands lowered from the source A pose")
	var calm_skeleton: Skeleton3D = calm.find_child("Skeleton3D", true, false) as Skeleton3D
	var calm_hands: Dictionary = {}
	for name: String in ["RightHand", "LeftHand"]:
		var point: Vector3 = calm_skeleton.global_transform * calm_skeleton.get_bone_global_pose(calm_skeleton.find_bone(name)).origin
		var target: Vector3 = Vector3(-0.24 if name == "RightHand" else 0.24, 0.96, 0.08)
		_expect(point.distance_to(target) < 0.001, "actual calm wrist reaches reviewed local target " + name)
		calm_hands[name] = [point.x, point.y, point.z]
	var calm_edges: Dictionary = _edge_stretch(rest_points, calm_points, indices)
	calm.free()
	source_model.free()
	candidate_model.free()
	var receipt: Dictionary = {"schema": 1, "runtime_selected": false,
		"source_sha256": SOURCE_SHA, "candidate_sha256": FileAccess.get_sha256(args[1]),
		"preserved": _preserved(original, prepared), "negative_controls": controls,
		"vertices": 19106, "triangles": 12456, "skin_joints": 24,
		"weighted_rest": prepared_rest, "maps": map_rows, "walk_samples": samples,
		"calm": calm_bounds, "calm_wrists_world": calm_hands, "calm_skin_edges": calm_edges,
		"external_hand_contact_verified": false, "failures": _failures}
	DirAccess.make_dir_recursive_absolute(args[2].get_base_dir())
	var file: FileAccess = FileAccess.open(args[2], FileAccess.WRITE)
	if file == null:
		_fail("cannot write validation receipt")
		return
	file.store_string(JSON.stringify(receipt, "\t") + "\n")
	file.close()
	if not _failures.is_empty():
		_fail("; ".join(_failures))
		return
	print("validate_tern_source: PASS (unchanged imported geometry, skin and 8 walk phases; UV/winding/weight controls rejected)")
	quit(0)

func _preserved(original: Dictionary, prepared: Dictionary) -> bool:
	var a: Dictionary = original.document
	var b: Dictionary = prepared.document
	for key: String in ["accessors", "meshes", "nodes", "skins", "animations", "scenes", "scene"]:
		if a.get(key) != b.get(key):
			print_verbose("preservation section differs: " + key)
			return false
	if a.asset.get("copyright", "") != b.asset.get("copyright", "") or b.asset.has("generator"):
		return false
	if a.bufferViews.size() != b.bufferViews.size():
		return false
	var image_views: Array[int] = []
	for image: Dictionary in a.images:
		image_views.append(int(image.bufferView))
	for index: int in range(a.bufferViews.size()):
		if index in image_views:
			continue
		var av: Dictionary = a.bufferViews[index]
		var bv: Dictionary = b.bufferViews[index]
		var ao: int = int(av.get("byteOffset", 0))
		var bo: int = int(bv.get("byteOffset", 0))
		if av.byteLength != bv.byteLength or original.binary.slice(ao, ao + int(av.byteLength)) != prepared.binary.slice(bo, bo + int(bv.byteLength)):
			print_verbose("preservation buffer view differs: %d" % index)
			return false
	return true

func _load_model(path: String) -> Node3D:
	var document: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	return document.generate_scene(state) if document.append_from_file(path, state) == OK else null

func _mesh(model: Node3D) -> MeshInstance3D:
	return model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D

func _bounds(points: PackedVector3Array) -> Dictionary:
	if points.is_empty():
		return {"min_y": INF, "height": 0.0}
	var bounds: AABB = AABB(points[0], Vector3.ZERO)
	for point: Vector3 in points:
		bounds = bounds.expand(point)
	return {"min_y": bounds.position.y, "height": bounds.size.y,
		"position": [bounds.position.x, bounds.position.y, bounds.position.z],
		"size": [bounds.size.x, bounds.size.y, bounds.size.z]}

func _edge_stretch(rest: PackedVector3Array, posed: PackedVector3Array, indices: PackedInt32Array) -> Dictionary:
	var maximum: float = 1.0
	var edges_over_two: int = 0
	var measured: int = 0
	for triangle: int in range(0, indices.size(), 3):
		for edge: int in range(3):
			var a: int = indices[triangle + edge]
			var b: int = indices[triangle + (edge + 1) % 3]
			var length: float = rest[a].distance_to(rest[b])
			if length < 0.00001:
				continue
			var ratio: float = posed[a].distance_to(posed[b]) / length
			maximum = maxf(maximum, ratio)
			edges_over_two += int(ratio > 2.0)
			measured += 1
	return {"minimum_rest_length_m": 0.00001, "triangle_edges_measured": measured,
		"maximum_ratio": maximum, "edges_over_two": edges_over_two}

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _fail(message: String) -> void:
	push_error("validate_tern_source: " + message)
	quit(1)
