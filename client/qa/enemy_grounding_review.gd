extends SceneTree

## Real pawn frames under controlled support, with an explicit stale-cache control.
const GROUPS: Array = [
	["clerk", "sweeper", "heavy_sweeper", "turret"],
	["ranged_sweeper", "auditor", "enforcer", "redactor"],
	["jammer", "crawler"],
]
var _viewport: SubViewport
var _camera: Camera3D
var _actors: Array[Node3D] = []
var _rows: Array[Dictionary] = []
var _title: Label

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2 or not args[1] in ["before", "after"]:
		push_error("enemy_grounding_review: require output directory and before/after")
		quit(1)
		return
	var output: String = args[0]
	var mode: String = args[1]
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		quit(1)
		return
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280, 720)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("242b33")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("c3c6b9")
	world.environment.ambient_light_energy = 0.65
	_viewport.add_child(world)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -30, 0)
	light.light_energy = 1.2
	_viewport.add_child(light)
	_camera = Camera3D.new()
	_camera.fov = 60
	_viewport.add_child(_camera)
	var canvas: CanvasLayer = CanvasLayer.new()
	_viewport.add_child(canvas)
	_title = Label.new()
	_title.position = Vector2(24, 20)
	_title.add_theme_font_size_override("font_size", 24)
	canvas.add_child(_title)
	var scene: PackedScene = load("res://scenes/player.tscn")
	for floor_y: float in [0.0, 2.4]:
		var support: MeshInstance3D = AssessorRig.part("AuthoritativeSupportReference", Vector3(12, 0.2 + floor_y, 8), Vector3(0, floor_y * 0.5 - 0.1, 0), Color("464c4c"))
		_viewport.add_child(support)
		var line: MeshInstance3D = AssessorRig.part("ContactReference", Vector3(12, 0.008, 0.025), Vector3(0, floor_y + 0.004, 0.24), Color("a9956f"))
		_viewport.add_child(line)
		var post: MeshInstance3D = AssessorRig.part("1.8MetreReference", Vector3(0.1, 1.8, 0.1), Vector3(-5, floor_y + 0.9, 0), Color("bdab86"))
		_viewport.add_child(post)
		_camera.position = Vector3(0, floor_y + 1.62, 7)
		_camera.look_at(Vector3(0, floor_y + 0.9, 0))
		for group: Array in GROUPS:
			for phase: String in ["idle", "hit", "dead"]:
				var samples: Array[Dictionary] = []
				for index: int in range(group.size()):
					var kind: String = group[index]
					var x: float = (index - (group.size() - 1) * 0.5) * 2.4
					var pawn: Node3D = scene.instantiate()
					_viewport.add_child(pawn)
					_actors.append(pawn)
					pawn.set_process(false)
					pawn.set_player_data(kind, kind)
					pawn.position = Vector3(x, floor_y + 1.5, 0)
					var state: Dictionary = {"id":kind, "x":x, "y":floor_y + 1.5, "z":0.0, "yaw":0.0,
						"hp":0 if phase == "dead" else 60, "weapon":"Tack", "campaign":{
							"side":"union", "kind":kind, "phase":phase, "phase_started":100, "phase_ends":140}}
					pawn.update_state(state, 139 if phase == "dead" else 105)
					var body: Sprite3D = pawn.get_node("Body")
					if mode == "before":
						pawn._body_rest_y = -0.15
						if kind in ["heavy_sweeper", "jammer", "crawler"]:
							var old_image: Image = Image.load_from_file("res://../.agents/enemy-grounding-20261008/atlas-before/" + kind + ".png")
							assert(old_image != null and not old_image.is_empty())
							body.texture = ImageTexture.create_from_image(old_image)
							body.material_override.set_shader_parameter("sprite_texture", body.texture)
					pawn.broadcast_scale_enabled = true
					pawn.hit_flash_timer = 0.12 if phase == "hit" else 0.0
					for frame: int in range(3):
						pawn._process(0.02)
					pawn.get_node("Label3D").visible = false
					var tile: int = body.texture.get_width() / body.hframes
					var origin: Vector2i = Vector2i(body.frame % body.hframes, body.frame / body.hframes) * tile
					var used: Rect2i = body.texture.get_image().get_region(Rect2i(origin, Vector2i.ONE * tile)).get_used_rect()
					var bottom: float = body.global_position.y + (tile * 0.5 - used.end.y) * body.pixel_size
					samples.append({"kind":kind,"phase":phase,"server_y":state.y,"support_y":floor_y,
						"sprite_origin_y":body.position.y,"frame":body.frame,"visible_bottom_y":bottom,
						"offset_m":bottom - floor_y,"scale":[body.scale.x,body.scale.y,body.scale.z]})
					var label: Label3D = Label3D.new()
					label.text = kind.replace("_", " ")
					label.position = Vector3(x, floor_y + 2.2, 0)
					label.font_size = 28
					label.pixel_size = 0.005
					_viewport.add_child(label)
					_actors.append(label)
				_title.text = ("Controlled stale-origin reproduction" if mode == "before" else "Corrected pawn registration and source poses") + " | " + phase + " | support %.1f m" % floor_y
				await process_frame
				await RenderingServer.frame_post_draw
				var name: String = "%s_%02d_%s_floor_%s" % [mode, _rows.size(), phase, str(floor_y).replace(".", "_")]
				var path: String = output.path_join(name + ".png")
				assert(_viewport.get_texture().get_image().save_png(path) == OK)
				_rows.append({"file":name + ".png","sha256":FileAccess.get_sha256(path),"samples":samples})
				for actor: Node3D in _actors:
					actor.free()
				_actors.clear()
		post.free()
		line.free()
		support.free()
	var sources: Dictionary = {}
	for source: String in ["res://scripts/player_pawn.gd", "res://scripts/enemy_view.gd", "res://qa/enemy_grounding_review.gd", "res://assets/characters/union/heavy_sweeper.png", "res://assets/characters/union/jammer.png", "res://assets/characters/union/crawler.png"]:
		sources[source] = FileAccess.get_sha256(source)
	var receipt: FileAccess = FileAccess.open(output.path_join("review.json"), FileAccess.WRITE)
	assert(receipt != null)
	receipt.store_string(JSON.stringify({"schema":1,"mode":mode,"controlled_fixture":true,"ordinary_play_acceptance":false,
		"stale_cache_negative":mode == "before","sources":sources,"gpu":RenderingServer.get_video_adapter_name(),
		"renderer":RenderingServer.get_current_rendering_method(),"states":_rows}, "\t") + "\n")
	receipt.close()
	_viewport.free()
	await process_frame
	print("enemy_grounding_review: PASS, 18 controlled real-pawn support states")
	quit(0)
