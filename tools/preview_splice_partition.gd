extends SceneTree

## Static original and rejected-label controls only, without joints or motion.
const SOURCE: String = "res://../art/raw/meshy-pilot-20261003/splice-named-v1-ultra-0.glb"
const SOURCE_SHA: String = "4560940190c9877b78885e3138c5e3628e9bfe906474ca14f54986931bbe19f1"
const LABEL_SHA: String = "9fd7107e7184738c2a2175f3441e0252985983220aebf9734748410522273f5e"
var _viewport: SubViewport
var _camera: Camera3D
var _rows: Array[Dictionary] = []
var _out: String

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2 or not args[0].is_absolute_path() or not args[1].is_absolute_path() or \
		FileAccess.get_sha256(SOURCE) != SOURCE_SHA or FileAccess.get_sha256(args[0]) != LABEL_SHA or \
		DirAccess.make_dir_recursive_absolute(args[1]) != OK:
		_fail("pinned original, rejected labels and absolute output required")
		return
	_out = args[1]
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1024,768)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("222831")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c1c8cd")
	environment.environment.ambient_light_energy = 0.55
	_viewport.add_child(environment)
	for angles: Vector2 in [Vector2(-35,-35),Vector2(-20,145)]:
		var light: DirectionalLight3D = DirectionalLight3D.new()
		light.rotation_degrees = Vector3(angles.x,angles.y,0)
		light.light_energy = 1.3 if angles.y < 0 else 0.65
		_viewport.add_child(light)
	var floor_mesh: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(4,4)
	floor_mesh.mesh = plane
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color("353e45")
	material.roughness = 1.0
	floor_mesh.material_override = material
	_viewport.add_child(floor_mesh)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 2.15
	_viewport.add_child(_camera)
	for index: int in 2:
		var path: String = SOURCE if index == 0 else args[0]
		var label: String = "original" if index == 0 else "rejected_labels"
		var document: GLTFDocument = GLTFDocument.new()
		var state: GLTFState = GLTFState.new()
		if document.append_from_file(path,state) != OK:
			_fail("cannot decode " + label)
			return
		var figure: Node3D = document.generate_scene(state)
		var triangles: int = 0
		var bounds: AABB
		var first: bool = true
		for child: Node in figure.find_children("*","MeshInstance3D",true,false):
			var mesh: MeshInstance3D = child as MeshInstance3D
			for surface: int in mesh.mesh.get_surface_count():
				var arrays: Array = mesh.mesh.surface_get_arrays(surface)
				triangles += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size()/3
				for point: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
					var transformed: Vector3 = mesh.transform * point
					if first:
						bounds = AABB(transformed,Vector3.ZERO)
						first = false
					else:
						bounds = bounds.expand(transformed)
		if first or triangles != 16602 or bounds.size.y < 1.89 or bounds.size.y > 1.90:
			figure.free()
			_fail("actual original geometry count or bounds lost")
			return
		var scale_factor: float = 1.8 / bounds.size.y
		figure.scale = Vector3.ONE * scale_factor
		figure.position.y = -bounds.position.y * scale_factor
		_viewport.add_child(figure)
		for angle: int in 4:
			_camera.size = 2.15
			_camera.position = Vector3(sin(angle*PI*0.5+0.12)*4,1.12,cos(angle*PI*0.5+0.12)*4)
			_camera.look_at(Vector3(0,0.9,0))
			if not await _capture("%s_full_%d" % [label,angle],triangles,scale_factor):
				return
		for angle: int in 2:
			_camera.size = 1.15
			_camera.position = Vector3(0.1,1.10,3.0 if angle == 0 else -3.0)
			_camera.look_at(Vector3(0,1.05,0))
			if not await _capture("%s_hip_wrists_%d" % [label,angle],triangles,scale_factor):
				return
		figure.free()
	var receipt: FileAccess = FileAccess.open(_out.path_join("preview.json"),FileAccess.WRITE)
	if receipt == null:
		_fail("cannot retain preview receipt")
		return
	receipt.store_string(JSON.stringify({"schema":1,"scope":"static original and rejected diagnostic labels, no moving partition or pivot acceptance","source_sha256":SOURCE_SHA,"labels_sha256":LABEL_SHA,"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"frames":_rows},"\t") + "\n")
	receipt.close()
	_viewport.free()
	await process_frame
	print("preview_splice_partition: PASS (12 static geometry controls; rejected labels remain unaccepted)")
	quit(0)

func _capture(label: String, triangles: int, scale_factor: float) -> bool:
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var picture: Image = _viewport.get_texture().get_image()
	var path: String = _out.path_join(label + ".png")
	if picture == null or picture.is_empty() or picture.save_png(path) != OK:
		_fail("empty or unwritable original-size control")
		return false
	_rows.append({"file":label+".png","sha256":FileAccess.get_sha256(path),"original_triangles":triangles,"uniform_scale":scale_factor,"height_m":1.8})
	return true

func _fail(reason: String) -> void:
	push_error("preview_splice_partition: " + reason)
	quit(1)
