extends SceneTree

const Prepared = preload("res://../tools/splice_prepared_source.gd")
const Rig = preload("res://../tools/splice_mechanical_rig.gd")

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 4 or not args[0].is_absolute_path() or not args[1].is_absolute_path() or not args[3].is_absolute_path() or FileAccess.file_exists(args[3]):
		_fail("absolute region, prepared artifact/hash and fresh receipt required")
		return
	var candidate: Dictionary = Prepared.load_candidate(args[0],args[1],args[2])
	if candidate.is_empty():
		_fail("pinned artifact or exported hierarchy/clips failed to load")
		return
	root.add_child(candidate.model)
	root.add_child(candidate.reference.root)
	Prepared.sample(candidate,"calm",0.0)
	Rig.pose(candidate.reference,0.0,false)
	var rest: float = Rig.rest_error(candidate)
	var height: float = float(Rig.measure(candidate).original_top_y)
	var floor_error: float = 0.0
	var source_error: float = 0.0
	var cap_error: float = 0.0
	var center_error: float = 0.0
	var rack_error: float = 0.0
	var frames: Array[Dictionary] = []
	var native_caps: Dictionary = Prepared.native_cap_geometry(candidate)
	if not native_caps.valid:
		candidate.model.free()
		candidate.reference.root.free()
		_fail("actual native cap topology differs")
		return
	var native_rim: float = 0.0
	var native_center: float = 0.0
	for clip: String in ["calm","walk"]:
		for index: int in 256:
			var phase: float = (float(index) + 0.371) / 256.0
			Prepared.sample(candidate,clip,phase)
			Rig.pose(candidate.reference,phase,clip == "walk")
			var actual: Dictionary = Rig.measure(candidate)
			var difference: float = Prepared.maximum_source_difference(candidate)
			var actual_caps: Dictionary = Prepared.measure_native_caps(candidate,native_caps)
			native_rim = maxf(native_rim,float(actual_caps.rim_error_m))
			native_center = maxf(native_center,float(actual_caps.center_error_m))
			floor_error = maxf(floor_error,absf(float(actual.original_floor_y)))
			source_error = maxf(source_error,difference)
			cap_error = maxf(cap_error,float(actual.maximum_cap_to_original_rim_error_m))
			center_error = maxf(center_error,float(actual.maximum_common_joint_center_error_m))
			rack_error = maxf(rack_error,float(actual.shared_parent_rack_transform_error))
			frames.append({"clip":clip,"phase":phase,"actual":actual,"maximum_original_surface_difference_m":difference})
	var controls: Dictionary = {}
	var cap_meshes_match: bool = Prepared.actual_cap_meshes_match(candidate)
	Prepared.sample(candidate,"walk",0.25)
	Rig.pose(candidate.reference,0.25,true)
	var positive_quarter: float = Prepared.maximum_source_difference(candidate)
	Prepared.sample(candidate,"walk",0.0)
	controls["frozen_actual_clip_fails_reference_motion"] = Prepared.maximum_source_difference(candidate) > 0.1
	Prepared.sample(candidate,"walk",0.25)
	candidate.root.position.y += 0.2
	controls["raised_exported_root_fails_support"] = absf(float(Rig.measure(candidate).original_floor_y)) > 0.19
	candidate.root.position.y -= 0.2
	candidate.parts[16].position.x += 0.06
	controls["detached_exported_rack_fails"] = float(Rig.measure(candidate).shared_parent_rack_transform_error) > 0.05
	candidate.parts[16].position.x -= 0.06
	candidate.closures[10][0].node.visible = false
	controls["missing_exported_cap_fails"] = not Rig.measure(candidate).closure_covers_original_boundary_edges
	candidate.closures[10][0].node.visible = true
	var cap: MeshInstance3D = candidate.closures[10][0].node
	var original_cap_mesh: Mesh = cap.mesh
	var changed_arrays: Array = cap.mesh.surface_get_arrays(0)
	var changed_vertices: PackedVector3Array = changed_arrays[Mesh.ARRAY_VERTEX]
	changed_vertices[0].x += 0.04
	changed_arrays[Mesh.ARRAY_VERTEX] = changed_vertices
	var changed_cap_mesh: ArrayMesh = ArrayMesh.new()
	changed_cap_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,changed_arrays)
	cap.mesh = changed_cap_mesh
	controls["altered_actual_exported_cap_surface_fails"] = not Prepared.actual_cap_meshes_match(candidate)
	cap.mesh = original_cap_mesh
	var passed: bool = cap_meshes_match and native_rim <= 0.00001 and native_center <= 0.00002 and rest <= 0.000001 and absf(height - 1.8) <= 0.00001 and floor_error <= 0.001 and source_error <= 0.001 and cap_error <= 0.000001 and center_error <= 0.000001 and rack_error <= 0.000001 and positive_quarter <= 0.00001 and not false in controls.values()
	var report: Dictionary = {"schema":1,"status":"native exported compact motion passed; renderer review remains open" if passed else "rejected native exported compact motion", "prepared_sha256":args[2],"sample_count":frames.size(),"sample_kind":"actual reloaded AnimationPlayer at off-grid phases","actual_native_cap_triangles_match_with_measured_tolerance":cap_meshes_match,"maximum_actual_native_cap_local_position_error_m":native_caps.maximum_local_position_error_m,"maximum_actual_native_cap_rim_error_m":native_rim,"maximum_actual_native_cap_center_error_m":native_center,"native_cap_tolerances_m":{"rim":0.00001,"center":0.00002},"rest_reconstruction_error_m":rest,"rest_height_m":height,"maximum_actual_floor_error_m":floor_error,"maximum_actual_original_surface_difference_m":source_error,"maximum_welded_witness_cap_rim_error_m":cap_error,"maximum_welded_witness_hinge_center_error_m":center_error,"maximum_actual_rack_error":rack_error,"actual_quarter_reference_error_m":positive_quarter,"negative_controls":controls,"samples":frames,"runtime_selected":false}
	var file: FileAccess = FileAccess.open(args[3],FileAccess.WRITE)
	if file == null:
		candidate.model.free()
		candidate.reference.root.free()
		_fail("cannot retain actual native motion receipt")
		return
	file.store_string(JSON.stringify(report,"\t") + "\n")
	file.close()
	candidate.model.free()
	candidate.reference.root.free()
	await process_frame
	if not passed:
		_fail("exported native geometry, motion or actual negative control failed")
		return
	print("validate_splice_prepared: PASS (512 actual exported off-grid phases and five actual failure controls; renderer gate separate)")
	quit(0)

func _fail(reason: String) -> void:
	push_error("validate_splice_prepared: " + reason)
	quit(1)
