extends SceneTree

const Prepared = preload("res://../tools/splice_prepared_source.gd")
const Rig = preload("res://../tools/splice_mechanical_rig.gd")
var _viewport: SubViewport
var _camera: Camera3D
var _environment: Environment
var _key: DirectionalLight3D
var _fill: DirectionalLight3D
var _candidate: Dictionary
var _out: String
var _rows: Array[Dictionary] = []

func _initialize() -> void:
	set_meta("fragr_automated",true)
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 4 or not args[0].is_absolute_path() or not args[1].is_absolute_path() or not args[3].is_absolute_path() or FileAccess.file_exists(args[3].path_join("preview.json")):
		_fail("absolute regions, pinned prepared artifact/hash and fresh output required")
		return
	_candidate = Prepared.load_candidate(args[0],args[1],args[2])
	_out = args[3]
	if _candidate.is_empty() or DirAccess.make_dir_recursive_absolute(_out) != OK:
		_fail("prepared source fixture failed")
		return
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1024,768)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.background_color = Color("20272f")
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color("c1c8cd")
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = _environment
	_viewport.add_child(environment)
	_key = DirectionalLight3D.new()
	_key.rotation_degrees = Vector3(-35,-35,0)
	_viewport.add_child(_key)
	_fill = DirectionalLight3D.new()
	_fill.rotation_degrees = Vector3(-20,145,0)
	_viewport.add_child(_fill)
	var floor_mesh: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(4,4)
	floor_mesh.mesh = plane
	var floor_material: StandardMaterial3D = StandardMaterial3D.new()
	floor_material.albedo_color = Color("353e45")
	floor_material.roughness = 1.0
	floor_mesh.material_override = floor_material
	_viewport.add_child(floor_mesh)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_viewport.add_child(_camera)
	_viewport.add_child(_candidate.reference.root)
	_viewport.add_child(_candidate.model)
	var controls: Array[Dictionary] = []
	for angle: int in 4:
		controls.append({"name":"rest_%d" % angle,"clip":"calm","phase":0.0,"angle":angle,"dim":false,"close":false,"distant":false})
	for phase: float in [0.25,0.75]:
		for angle: int in 4:
			controls.append({"name":"walk_%03d_%d" % [int(phase*1000),angle],"clip":"walk","phase":phase,"angle":angle,"dim":false,"close":false,"distant":false})
	for dim: bool in [false,true]:
		for angle: int in [0,2]:
			controls.append({"name":"joints_%d_%s" % [angle,"dim" if dim else "neutral"],"clip":"walk","phase":0.25,"angle":angle,"dim":dim,"close":true,"distant":false})
		controls.append({"name":"distant_" + ("dim" if dim else "neutral"),"clip":"walk","phase":0.25,"angle":0,"dim":dim,"close":false,"distant":true})
	for angle: int in [0,2]:
		controls.append({"name":"turn_%d" % angle,"clip":"calm","phase":0.25,"angle":angle,"dim":false,"close":false,"distant":false})
	for control: Dictionary in controls:
		_lighting(bool(control.dim))
		_view(int(control.angle),bool(control.close),bool(control.distant))
		Rig.pose(_candidate.reference,float(control.phase),control.clip == "walk")
		Prepared.sample(_candidate,control.clip,float(control.phase))
		for compact: bool in [false,true]:
			_candidate.model.visible = compact
			_candidate.reference.root.visible = not compact
			var actual: Dictionary = Rig.measure(_candidate) if compact else Rig.measure(_candidate.reference)
			actual["clip"] = control.clip
			actual["phase"] = control.phase
			actual["maximum_original_surface_difference_m"] = Prepared.maximum_source_difference(_candidate)
			if not await _capture(("compact_" if compact else "source_") + control.name,actual):
				return
	_lighting(false)
	_view(0,false,false)
	_candidate.model.visible = true
	_candidate.reference.root.visible = false
	var started: int = Time.get_ticks_usec()
	for frame: int in 96:
		var phase: float = float(frame % 48) / 48.0
		Prepared.sample(_candidate,"walk",phase)
		Rig.pose(_candidate.reference,phase,true)
		await create_timer(1.0/24.0,false).timeout
		var actual: Dictionary = Rig.measure(_candidate)
		actual["phase"] = phase
		actual["elapsed_us"] = Time.get_ticks_usec() - started
		actual["maximum_original_surface_difference_m"] = Prepared.maximum_source_difference(_candidate)
		if not await _capture("motion_%03d" % frame,actual):
			return
	var file: FileAccess = FileAccess.open(_out.path_join("preview.json"),FileAccess.WRITE)
	if file == null:
		_fail("compact original receipt unavailable")
		return
	file.store_string(JSON.stringify({"schema":1,"scope":"actual exported compact AnimationPlayer versus accepted source; no live runtime selection","source_sha256":Rig.RawAudit.SHA,"prepared_sha256":args[2],"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"paired_static_states":controls.size(),"static_originals":controls.size()*2,"timed_motion_originals":96,"frames":_rows},"\t") + "\n")
	file.close()
	_viewport.free()
	await process_frame
	print("preview_splice_prepared: PASS (40 paired static originals and 96 timed exported-clip frames; review separate)")
	quit(0)

func _lighting(dim: bool) -> void:
	_environment.ambient_light_energy = 0.18 if dim else 0.55
	_key.light_energy = 0.35 if dim else 1.3
	_fill.light_energy = 0.1 if dim else 0.65

func _view(angle: int, close: bool, distant: bool) -> void:
	_camera.size = 2.15
	_camera.position = Vector3(sin(angle*PI*0.5+0.12)*4,1.12,cos(angle*PI*0.5+0.12)*4)
	var target: Vector3 = Vector3(0,0.9,0)
	if close:
		_camera.size = 1.25
		_camera.position = Vector3(0.15 if angle == 0 else -0.15,0.95,3.0 if angle == 0 else -3.0)
		target = Vector3(0,0.95,0)
	elif distant:
		_camera.size = 4.0
		_camera.position = Vector3(0.5,1.4,5.0)
	_camera.look_at(target)

func _capture(label: String, actual: Dictionary) -> bool:
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var picture: Image = _viewport.get_texture().get_image()
	var path: String = _out.path_join(label + ".png")
	if picture == null or picture.is_empty() or picture.save_png(path) != OK:
		_fail("exported original capture unavailable")
		return false
	_rows.append({"file":label + ".png","sha256":FileAccess.get_sha256(path),"actual":actual,"lighting":{"ambient":_environment.ambient_light_energy,"key":_key.light_energy,"fill":_fill.light_energy}})
	return true

func _fail(reason: String) -> void:
	push_error("preview_splice_prepared: " + reason)
	quit(1)
