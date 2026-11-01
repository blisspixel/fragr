extends SceneTree

## Locational damage presentation lineup (#533): real Union pawns with the
## server's height bands drawn beside them (legs under 0.85 m, torso to
## 1.45 m, head to the crown, a Ranged Sweeper's mast column above it), a
## Ranged Sweeper with its mast intact and shot off, an absorbed Sweeper's
## cyan light where the red optic was, and the HUD's hit marker for every
## zone the server can report. Controlled presentation fixtures with no
## network play or outcome authority.
##
## Usage: godot --path client --script res://qa/zone_review.gd -- /abs/out
const SIZE: Vector2i = Vector2i(1280, 720)
## Server bands, metres above the feet (`combat.rs` LEG_GATE, HEAD_GATE,
## FIGHTER_HEIGHT, MAST_HEIGHT).
const LEG_GATE: float = 0.85
const HEAD_GATE: float = 1.45
const CROWN: float = 1.8
const MAST_BASE: float = 1.85
const MAST_TOP: float = 2.25
const MARKERS: Array[Array] = [
	["torso", 25, "Flechette", false], ["head", 37, "Flechette", false], ["legs", 18, "Flechette", false],
	["plate", 12, "Flechette", false], ["weak", 50, "Flechette", false], ["kill", 37, "Flechette", true],
]

var _viewport: SubViewport
var _camera: Camera3D
var _actors: Array[Node] = []
var _title: Label
var _canvas: CanvasLayer


func _initialize() -> void:
	set_meta("fragr_automated", true)
	set_meta("fragr_settings_path", "")
	set_meta("fragr_records_path", "")
	call_deferred("_run")


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1 or not args[0].is_absolute_path() or DirAccess.make_dir_recursive_absolute(args[0]) != OK:
		push_error("zone_review: require absolute output directory")
		quit(1)
		return
	var out: String = args[0]
	AudioServer.set_bus_mute(0, true)
	_stage()
	await _pawns(out, "bands_union", [
		{"kind": "sweeper", "side": "union"}, {"kind": "heavy_sweeper", "side": "union"},
		{"kind": "ranged_sweeper", "side": "union"}, {"kind": "turret", "side": "union"},
	], 0.0)
	await _pawns(out, "mast_and_light", [
		{"kind": "ranged_sweeper", "side": "union"}, {"kind": "ranged_sweeper", "side": "union", "mast_broken": true},
		{"kind": "sweeper", "side": "union"}, {"kind": "sweeper", "side": "inheritance", "control": "absorbed"},
	], 0.0)
	await _pawns(out, "mast_side", [
		{"kind": "ranged_sweeper", "side": "union"}, {"kind": "ranged_sweeper", "side": "union", "mast_broken": true},
	], PI * 0.5)
	await _markers(out)
	_viewport.free()
	for _frame: int in range(4):
		await process_frame
	print("zone_review: PASS")
	quit(0)


func _stage() -> void:
	_viewport = SubViewport.new()
	_viewport.size = SIZE
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("6b6e70")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("c3c6b9")
	world.environment.ambient_light_energy = 0.65
	_viewport.add_child(world)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -30, 0)
	light.light_energy = 1.2
	_viewport.add_child(light)
	_camera = Camera3D.new()
	# Orthographic and level, so a band reads at its true height beside the body.
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 4.6
	_camera.position = Vector3(0, 1.25, 7.5)
	_viewport.add_child(_camera)
	var floor_mesh: MeshInstance3D = AssessorRig.part("Floor", Vector3(14, 0.2, 8), Vector3(0, -0.1, 0), Color("464c4c"))
	_viewport.add_child(floor_mesh)
	_canvas = CanvasLayer.new()
	_viewport.add_child(_canvas)
	_title = Label.new()
	_title.position = Vector2(24, 20)
	_title.add_theme_font_size_override("font_size", 22)
	_canvas.add_child(_title)


## A thin translucent band from `low` to `high` behind a pawn at `x`.
func _band(x: float, low: float, high: float, colour: Color, width: float = 1.1) -> void:
	var band: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(width, high - low, 0.02)
	band.mesh = mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = colour
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	band.material_override = material
	band.position = Vector3(x, (low + high) * 0.5, -0.6)
	_viewport.add_child(band)
	_actors.append(band)


func _pawns(out: String, name: String, bodies: Array[Dictionary], yaw_offset: float) -> void:
	var scene: PackedScene = load("res://scenes/player.tscn")
	for index: int in range(bodies.size()):
		var spec: Dictionary = bodies[index]
		var kind: String = spec["kind"]
		var x: float = (index - (bodies.size() - 1) * 0.5) * 2.0
		_band(x, 0.0, LEG_GATE, Color(0.3, 0.6, 1.0, 0.28))
		_band(x, LEG_GATE, HEAD_GATE, Color(0.4, 1.0, 0.4, 0.22))
		_band(x, HEAD_GATE, CROWN, Color(1.0, 0.9, 0.2, 0.3))
		if kind == "ranged_sweeper" and not spec.get("mast_broken", false):
			_band(x, MAST_BASE, MAST_TOP, Color(1.0, 0.3, 0.9, 0.35), 0.4)
		var pawn: Node3D = scene.instantiate()
		_viewport.add_child(pawn)
		_actors.append(pawn)
		pawn.set_process(false)
		pawn.set_player_data(kind + str(index), kind)
		pawn.position = Vector3(x, 1.5, 0)
		var campaign: Dictionary = {"side": spec["side"], "kind": kind, "phase": "idle", "phase_started": 100, "phase_ends": 100}
		if spec.has("control"):
			campaign["control"] = spec["control"]
		if spec.get("mast_broken", false):
			campaign["mast_broken"] = true
		# Server yaw points along +X; the camera looks down -Z, so a body
		# facing the camera has yaw PI / 2.
		var state: Dictionary = {"id": kind + str(index), "x": x, "y": 1.5, "z": 0.0, "yaw": PI * 0.5 + yaw_offset,
			"hp": 60, "weapon": "Sniper" if kind == "ranged_sweeper" else "Flechette", "campaign": campaign}
		pawn.update_state(state, 105)
		pawn.broadcast_scale_enabled = false
		for _frame: int in range(3):
			pawn._process(0.02)
		var label: Node = pawn.get_node_or_null("Label3D")
		if label is Label3D:
			(label as Label3D).visible = false
		var tag: Label3D = Label3D.new()
		tag.text = kind.replace("_", " ") + (" mast off" if spec.get("mast_broken", false) else "") + (" absorbed" if spec.has("control") else "")
		tag.position = Vector3(x, 2.55, 0)
		tag.font_size = 26
		tag.pixel_size = 0.005
		_viewport.add_child(tag)
		_actors.append(tag)
	_title.text = "Zones: legs blue, torso green, head yellow, mast magenta | " + name
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = _viewport.get_texture().get_image()
	assert(image.save_png(out.path_join(name + ".png")) == OK)
	for actor: Node in _actors:
		actor.free()
	_actors.clear()


func _markers(out: String) -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	var hud: CanvasLayer = main.get_node("HUD")
	main.remove_child(hud)
	main.free()
	_viewport.add_child(hud)
	await process_frame
	var strip: Image = Image.create(160 * MARKERS.size(), 160, false, Image.FORMAT_RGBA8)
	_title.text = ""
	for index: int in range(MARKERS.size()):
		var row: Array = MARKERS[index]
		if bool(row[3]):
			hud.show_kill_marker()
		else:
			hud.show_hit_marker(int(row[1]), str(row[2]), str(row[0]))
		hud.set("hit_marker_timer", 10.0)
		# Floating damage numbers drift over the mark; the strip shows the mark.
		var numbers: Node = hud.get_node_or_null("DamageNumbers")
		if numbers != null:
			for child: Node in numbers.get_children():
				child.free()
		await process_frame
		await RenderingServer.frame_post_draw
		var frame: Image = _viewport.get_texture().get_image()
		var crop: Image = frame.get_region(Rect2i(SIZE / 2 - Vector2i(40, 40), Vector2i(80, 80)))
		crop.resize(160, 160, Image.INTERPOLATE_NEAREST)
		strip.blit_rect(crop, Rect2i(Vector2i.ZERO, Vector2i(160, 160)), Vector2i(160 * index, 0))
	assert(strip.save_png(out.path_join("markers_torso_head_legs_plate_weak_kill.png")) == OK)
	hud.free()
