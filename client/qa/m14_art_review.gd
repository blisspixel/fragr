extends SceneTree

## Controlled source and lighting review. Does not simulate M14 mission progress.
const Launch = preload("res://scripts/m14_launch.gd")
const Fixture = preload("res://scripts/test_m14_presentation.gd")
var _viewport: SubViewport
var _camera: Camera3D
var _out: String
var _rows: Array[Dictionary] = []

func _initialize() -> void:
	set_meta("fragr_automated",true)
	_run.call_deferred()

func _capture(label: String,eye: Vector3,target: Vector3) -> void:
	_camera.position = eye
	_camera.look_at(target)
	await process_frame
	await RenderingServer.frame_post_draw
	assert(_viewport.get_texture().get_image().save_png(_out.path_join(label+".png")) == OK)
	_rows.append({"file":label+".png","eye":[eye.x,eye.y,eye.z]})

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or DirAccess.make_dir_recursive_absolute(args[0]) != OK:
		push_error("m14_art_review: require output directory")
		quit(1)
		return
	_out = args[0]
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(960,720)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var environment := WorldEnvironment.new()
	environment.environment = ArenaSky.build_environment("Launch Authority")
	_viewport.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38,-35,0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	_viewport.add_child(sun)
	_camera = Camera3D.new()
	_camera.fov = 65
	_viewport.add_child(_camera)
	var floor: MeshInstance3D = AssessorRig.part("ReviewGround",Vector3(80,0.1,80),Vector3(0,-0.05,0),Color("805342"))
	_viewport.add_child(floor)
	var golden: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://golden/walker_vectors.json"))
	var walker := WalkerView.new()
	_viewport.add_child(walker)
	walker.set_process(false)
	walker.configure_map(golden["map"])
	var initial: Dictionary = {"type":"snapshot","map_id":golden["map"]["map_id"],"tick":0,"players":[],"walker":{"hp":900,"stage":1,"phase":"dormant","phase_started":0,"phase_ends":0,"feet":[0,0,0],"target":[-12,0,-8],"artillery_targets":[[-8,0,-8],[-12,0,-8],[-16,0,-8]],"shells_left":36,"shells":[]}}
	walker.apply(initial)
	for step: int in range(8):
		var sample: Dictionary = initial.duplicate(true)
		sample["tick"] = step+1
		sample["walker"].merge({"phase":"relocating","phase_started":1,"phase_ends":401,"feet":[step*0.25,0,0]},true)
		walker.apply(sample)
		await _capture("relocation_%02d" % step,Vector3(6+step*0.25,1.8,-7),Vector3(step*0.25,1.8,0))
	walker.free()
	var view: Node3D = Launch.new()
	_viewport.add_child(view)
	view.wreck = Node3D.new()
	view.add_child(view.wreck)
	var boxes: Array[AABB] = Fixture.fallen_boxes()
	view._build_fallen_hull(boxes[0])
	for index: int in range(1,5):
		view._build_folded_leg(boxes[index],index)
	await _capture("fallen_front",Vector3(7,1.8,-9),Vector3(0,0.6,0))
	await _capture("fallen_rear",Vector3(-7,1.8,9),Vector3(0,0.6,0))
	await _capture("fallen_roof",Vector3(6,7,-8),Vector3(0,0.6,0))
	view.clear_map()
	floor.free()
	# Read retained development architecture, converting only its authored boxes
	# for a presentation fixture. No synthetic mission outcome is sent to a server.
	var authored: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../server/maps/test/launch_authority_development.json"))
	var info: Dictionary = {"map_id":1014,"map_name":"Launch Authority","geometry_version":2,"half_extent":authored["half_extent"],"solids":[],"presentation":{"ground":authored["ground"],"solids":[],"decorations":[]}}
	for solid: Dictionary in authored["solids"]:
		info["solids"].append({"min_x":solid["min"][0],"bottom":solid["min"][1],"min_z":solid["min"][2],"max_x":solid["max"][0],"top":solid["max"][1],"max_z":solid["max"][2]})
		info["presentation"]["solids"].append(solid["surface"])
	var cover := ArenaCover.new()
	_viewport.add_child(cover)
	cover.apply_map_info(info)
	view._build_launch_services(info)
	await _capture("launch_arrival",Vector3(-30,1.8,-37),Vector3(5,10,43))
	await _capture("launch_control_held",Vector3(5,1.8,39),Vector3(5,2,46.5))
	await _capture("settlement_cargo",Vector3(21,1.8,30),Vector3(29,8,40))
	view._pad_material.albedo_color = Launch.RELEASED
	view._pad_material.emission = Launch.RELEASED*0.3
	view._control_sign.configure("M14_PAD_RELEASED",view._control_sign.bounds,MenuTheme.BONE)
	await _capture("launch_control_released_fixture",Vector3(5,1.8,39),Vector3(5,2,46.5))
	var file := FileAccess.open(_out.path_join("review.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"controlled_fixture":true,"ordinary_mission_acceptance":false,"renderer":RenderingServer.get_current_rendering_method(),"device":RenderingServer.get_video_adapter_name(),"walker_source_sha256":FileAccess.get_sha256("res://scripts/walker_view.gd"),"m14_source_sha256":FileAccess.get_sha256("res://scripts/m14_launch.gd"),"states":_rows},"\t")+"\n")
	file.close()
	_viewport.free()
	await process_frame
	print("m14_art_review: PASS bounded controlled presentation views")
	quit(0)
