extends SceneTree

const Glb = preload("res://../tools/tern_glb.gd")
const Weighted = preload("res://art/models/tern_source.gd")
const SOURCE_SHA: String = "bb5511f280147bb3f4fa81db6ce1b42a58cb10daebdf486def6a807d3286693f"

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 3 or FileAccess.get_sha256(args[0]) != SOURCE_SHA:
		_fail("require pinned original, report path and one or more comparison GLBs")
		return
	var original: Dictionary = Glb.read(args[0])
	if original.is_empty():
		_fail("original container invalid")
		return
	var rows: Array[Dictionary] = []
	for path: String in [args[0]] + Array(args.slice(2)):
		var row: Dictionary = await _measure(path)
		if row.is_empty():
			return
		rows.append(row)
	var file: FileAccess = FileAccess.open(args[1], FileAccess.WRITE)
	if file == null:
		_fail("report write failed")
		return
	file.store_string(JSON.stringify({"schema": 1, "source_sha256": SOURCE_SHA,
		"scope": "Whole indexed edges and coincident source seams, raw retained walking clip; diagnostic, not source acceptance",
		"phases": 64, "rows": rows}, "\t") + "\n")
	file.close()
	print("audit_edda_skin: PASS (%d measured sources; diagnostic, no acceptance inferred)" % rows.size())
	quit(0)

func _measure(path: String) -> Dictionary:
	var document: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	if document.append_from_file(path, state) != OK:
		_fail("source import failed")
		return {}
	var model: Node3D = document.generate_scene(state)
	root.add_child(model)
	var instances: Array[Node] = model.find_children("*", "MeshInstance3D", true, false)
	var skeleton: Skeleton3D = model.get_node_or_null("Armature/Skeleton3D") as Skeleton3D
	var player: AnimationPlayer = model.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if instances.size() != 1 or skeleton == null or player == null or player.get_animation_list().is_empty():
		model.free()
		_fail("unexpected source hierarchy")
		return {}
	var instance: MeshInstance3D = instances[0] as MeshInstance3D
	var arrays: Array = instance.mesh.surface_get_arrays(0)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var rest: PackedVector3Array = Weighted.weighted_points(model)
	if positions.size() != 17561 or indices.size() != 14694 * 3 or rest.size() != positions.size():
		model.free()
		_fail("unexpected primitive counts")
		return {}
	var edges: Dictionary[Vector2i, float] = {}
	for face: int in range(0, indices.size(), 3):
		for corner: int in range(3):
			var a: int = indices[face + corner]
			var b: int = indices[face + (corner + 1) % 3]
			var key: Vector2i = Vector2i(mini(a, b), maxi(a, b))
			edges[key] = rest[a].distance_to(rest[b])
	var seams: Dictionary[Vector3i, PackedInt32Array] = {}
	for vertex: int in range(positions.size()):
		var point: Vector3 = rest[vertex]
		var key: Vector3i = Vector3i(roundi(point.x * 1000000), roundi(point.y * 1000000), roundi(point.z * 1000000))
		if not seams.has(key):
			seams[key] = PackedInt32Array()
		seams[key].append(vertex)
	var pairs: Array[Vector2i] = []
	for key: Vector3i in seams:
		var group: PackedInt32Array = seams[key]
		for index: int in range(1, group.size()):
			pairs.append(Vector2i(group[0], group[index]))
	var animation: Animation = player.get_animation(player.get_animation_list()[0])
	var maximum_ratio: float = 0.0
	var maximum_gap: float = 0.0
	var worst_edge: Dictionary = {}
	var worst_seam: Dictionary = {}
	var phase_rows: Array[Dictionary] = []
	var edge_worst: Dictionary[Vector2i, Dictionary] = {}
	for sample: int in range(64):
		var phase: float = (sample + 0.37) / 64.0
		skeleton.reset_bone_poses()
		_sample(animation, skeleton, phase)
		var posed: PackedVector3Array = Weighted.weighted_points(model)
		var phase_ratio: float = 0.0
		var phase_gap: float = 0.0
		for key: Vector2i in edges:
			if edges[key] < 0.0000001:
				continue
			var length: float = posed[key.x].distance_to(posed[key.y])
			var ratio: float = length / edges[key]
			phase_ratio = maxf(phase_ratio, ratio)
			if ratio > float(edge_worst.get(key, {}).get("ratio", 0.0)):
				edge_worst[key] = {"a": key.x, "b": key.y, "rest_a": _point(rest[key.x]), "rest_b": _point(rest[key.y]),
					"posed_a": _point(posed[key.x]), "posed_b": _point(posed[key.y]), "rest_length_m": edges[key],
					"posed_length_m": length, "ratio": ratio, "phase": phase}
			if ratio > maximum_ratio:
				maximum_ratio = ratio
				worst_edge = edge_worst[key]
		for pair: Vector2i in pairs:
			var gap: float = posed[pair.x].distance_to(posed[pair.y])
			phase_gap = maxf(phase_gap, gap)
			if gap > maximum_gap:
				maximum_gap = gap
				worst_seam = {"a": pair.x, "b": pair.y, "source_a": _point(rest[pair.x]), "source_b": _point(rest[pair.y]),
					"posed_a": _point(posed[pair.x]), "posed_b": _point(posed[pair.y]), "gap_m": gap, "phase": phase}
		phase_rows.append({"phase": phase, "maximum_edge_ratio": phase_ratio, "maximum_coincident_seam_gap_m": phase_gap})
		if sample % 8 == 0:
			await process_frame
	var ranked: Array = edge_worst.values()
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.ratio > b.ratio)
	var top: Array = ranked.slice(0, 80)
	var witnesses: Array[Dictionary] = []
	for pair: Vector2i in [Vector2i(11225, 11226), Vector2i(15027, 15029), Vector2i(6239, 6240), Vector2i(8425, 8426)]:
		witnesses.append(edge_worst.get(pair, {"a": pair.x, "b": pair.y, "missing": true}))
	var result: Dictionary = {"path": path, "sha256": FileAccess.get_sha256(path), "vertices": positions.size(),
		"triangles": indices.size() / 3, "edges": edges.size(), "coincident_pairs": pairs.size(),
		"clip": str(player.get_animation_list()[0]), "clip_seconds": animation.length,
		"maximum_edge_ratio": maximum_ratio, "maximum_coincident_seam_gap_m": maximum_gap,
		"worst_edge": worst_edge, "worst_seam": worst_seam, "top_edges": top, "witness_edges": witnesses,
		"all_edge_maxima": ranked, "phase_rows": phase_rows}
	model.free()
	await process_frame
	print("audit_edda_skin: measured %s (edge %.6f, seam %.6fm)" % [path.get_file(), maximum_ratio, maximum_gap])
	return result

static func _sample(animation: Animation, skeleton: Skeleton3D, phase: float) -> void:
	for track: int in range(animation.get_track_count()):
		var path: NodePath = animation.track_get_path(track)
		if path.get_subname_count() != 1:
			continue
		var bone: int = skeleton.find_bone(String(path.get_subname(0)))
		if bone < 0:
			continue
		var seconds: float = phase * animation.length
		match animation.track_get_type(track):
			Animation.TYPE_POSITION_3D:
				var position: Vector3 = animation.position_track_interpolate(track, seconds)
				if skeleton.get_bone_name(bone) == "Hips":
					position.x = skeleton.get_bone_rest(bone).origin.x
					position.z = skeleton.get_bone_rest(bone).origin.z
				skeleton.set_bone_pose_position(bone, position)
			Animation.TYPE_ROTATION_3D:
				skeleton.set_bone_pose_rotation(bone, animation.rotation_track_interpolate(track, seconds))
			Animation.TYPE_SCALE_3D:
				skeleton.set_bone_pose_scale(bone, animation.scale_track_interpolate(track, seconds))

static func _point(point: Vector3) -> Array[float]:
	return [point.x, point.y, point.z]

func _fail(message: String) -> void:
	push_error("audit_edda_skin: " + message)
	quit(1)
