extends SceneTree

const Rig = preload("res://../tools/splice_mechanical_rig.gd")
var _out: String

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 3 or not args[0].is_absolute_path() or not args[2].is_absolute_path():
		_fail("absolute diagnostic input, exact candidate hash and output required")
		return
	_out = args[2]
	var rig: Dictionary = Rig.build(args[0], args[1])
	if rig.is_empty():
		_fail("exact original triangle candidate failed to load")
		return
	root.add_child(rig.root)
	Rig.pose(rig, 0.0, false)
	var rest_error: float = Rig.rest_error(rig)
	var resting: Dictionary = Rig.measure(rig)
	if rest_error > 0.000001 or absf(float(resting.original_top_y) - 1.8) > 0.00001:
		rig.root.free()
		_fail("reversible 1.8 m rest reconstruction failed")
		return
	var frames: Array[Dictionary] = []
	var floor_error: float = 0.0
	var worst_seam: float = 0.0
	var worst_rim: float = 0.0
	var worst_center: float = 0.0
	var worst_rack: float = 0.0
	for walking: bool in [false, true]:
		for sample: int in 128:
			var phase: float = (sample + 0.217) / 128.0
			Rig.pose(rig, phase, walking)
			var measured: Dictionary = Rig.measure(rig)
			if not measured.valid or not measured.closure_covers_original_boundary_edges:
				if measured.valid:
					_write({"status":"rejected moving closure", "walking":walking, "sample":sample, "actual":measured})
				rig.root.free()
				_fail("actual original boundary escapes candidate closure")
				return
			floor_error = maxf(floor_error, absf(float(measured.original_floor_y)))
			worst_seam = maxf(worst_seam, float(measured.maximum_original_seam_gap_m))
			worst_rim = maxf(worst_rim, float(measured.maximum_cap_to_original_rim_error_m))
			worst_center = maxf(worst_center, float(measured.maximum_common_joint_center_error_m))
			worst_rack = maxf(worst_rack, float(measured.shared_parent_rack_transform_error))
			frames.append({"walking":walking, "phase":phase, "actual":measured})
	if floor_error > 0.000001 or worst_rack > 0.000001:
		rig.root.free()
		_fail("actual supported sole or shared rack parent failed")
		return
	var controls: Dictionary = {}
	Rig.pose(rig, 0.25, true)
	rig.closures[10][0].node.visible = false
	controls["omitted_moving_joint_closure"] = not Rig.measure(rig).closure_covers_original_boundary_edges
	rig.closures[10][0].node.visible = true
	rig.parts[16].position.x += 0.06
	controls["detached_stored_rack"] = float(Rig.measure(rig).shared_parent_rack_transform_error) > 0.05
	rig.parts[16].position.x -= 0.06
	Rig.pose(rig, 0.0, false)
	rig.parts[0].position.x += 0.4
	rig.meshes[0].position.x -= 0.4
	var displaced_rest_error: float = Rig.rest_error(rig)
	Rig.pose(rig, 0.25, false)
	controls["displaced_pivot_rest_still_matches"] = displaced_rest_error < 0.000001
	controls["displaced_pivot_fails_actual_motion"] = not Rig.measure(rig).closure_covers_original_boundary_edges
	rig.parts[0].position.x -= 0.4
	rig.meshes[0].position.x += 0.4
	Rig.pose(rig, 0.25, true)
	rig.root.position.y += 0.2
	controls["floating_source"] = float(Rig.measure(rig).original_floor_y) > 0.19
	Rig.pose(rig, 0.25, true)
	var first: Vector3 = rig.meshes[12].global_transform * rig.vertices[12][0]
	Rig.pose(rig, 0.75, true)
	var second: Vector3 = rig.meshes[12].global_transform * rig.vertices[12][0]
	var actual_walk_displacement: float = first.distance_to(second)
	controls["actual_indexed_sole_moves"] = actual_walk_displacement > 0.10
	var joints: Array[Dictionary] = []
	for part: int in rig.parts.size():
		var pivot: Vector3 = rig.pivots[part]
		joints.append({"part":Rig.Regions.PARTS[part], "parent":Rig.Regions.PARTS[Rig.PARENTS[part]] if Rig.PARENTS[part] >= 0 else "source_root", "source_pivot_m":[pivot.x, pivot.y, pivot.z], "measured_boundary_circumradius_m":rig.radii[part], "actual_indexed_vertices":rig.vertices[part].size()})
	var receipt: Dictionary = {"schema":1, "status":"source-only geometry candidate, renderer and motion inspection pending", "closure_kind":"paired actual original edge caps", "original_source_sha256":Rig.RawAudit.SHA, "regions_sha256":rig.candidate_sha256, "original_triangles":rig.original_triangles, "added_closure_triangles":rig.added_closure_triangles, "closure_rows":rig.closure_rows, "uniform_scale":rig.scale, "rest_height_m":resting.original_top_y, "rest_reconstruction_error_m":rest_error, "maximum_actual_floor_error_m":floor_error, "maximum_actual_original_seam_gap_m":worst_seam, "maximum_actual_cap_to_original_rim_error_m":worst_rim, "maximum_actual_common_joint_center_error_m":worst_center, "maximum_shared_parent_rack_error":worst_rack, "actual_walking_sole_displacement_m":actual_walk_displacement, "negative_controls":controls, "joints":joints, "sample_count":frames.size(), "actual_samples":frames}
	var saved: bool = _write(receipt)
	rig.root.free()
	await process_frame
	if not saved or false in controls.values():
		_fail("meaningful source motion negative control failed")
		return
	print("test_splice_mechanical_rig: PASS (256 actual geometry phases, exact rest, supported soles, retained rack and four failure controls)")
	quit(0)

func _write(value: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(_out, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(value, "\t") + "\n")
		file.close()
		return true
	return false

func _fail(reason: String) -> void:
	push_error("test_splice_mechanical_rig: " + reason)
	quit(1)
