extends SceneTree

## Union attack tell lineup: the actual campaign pawns, side by side, in each
## moment of an attack (at rest, the tick a tell starts, late in the tell and
## in the burst), at 5 and 15 metres under a dim interior light. Red optics are
## the Union attack tell light; this is where their flash and swell are judged
## against the rest of the body. Controlled presentation fixtures with no
## network play or outcome authority.
##
## Usage: godot --path client --script res://qa/union_tell_review.gd -- /abs/out
const KINDS: Array[String] = ["clerk", "sweeper", "heavy_sweeper", "auditor", "redactor", "turret"]
const WEAPONS: Dictionary[String, String] = {"clerk": "Tack", "sweeper": "Flechette",
	"heavy_sweeper": "Flechette", "auditor": "Tack", "redactor": "Shiv", "turret": "Rail"}
## Each moment: phase, ticks since it began, and its length in ticks.
const MOMENTS: Array[Dictionary] = [
	{"label": "rest", "phase": "moving", "age": 10, "length": 0},
	{"label": "tell_start", "phase": "windup", "age": 0, "length": 12},
	{"label": "tell_late", "phase": "windup", "age": 10, "length": 12},
	{"label": "burst", "phase": "firing", "age": 1, "length": 9},
]
const DISTANCES: Array[float] = [5.0, 15.0]
const SPACING: float = 1.6
const EYE: float = 1.6
const FEET: float = 1.5

var _viewport: SubViewport
var _camera: Camera3D
var _out: String
var _pawns: Array[Node3D] = []
var _failures: PackedStringArray = []
var _tick: int = 100


func _initialize() -> void:
	set_meta("fragr_automated", true)
	set_meta("fragr_settings_path", "")
	set_meta("fragr_records_path", "")
	call_deferred("_run")


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1 or not args[0].is_absolute_path() or DirAccess.make_dir_recursive_absolute(args[0]) != OK:
		push_error("union_tell_review: require absolute output directory")
		quit(1)
		return
	_out = args[0]
	AudioServer.set_bus_mute(0, true)
	_stage()
	for index: int in range(KINDS.size()):
		_pawns.append(_subject(index))
	# Campaign actors ease toward their accepted facing; let them arrive.
	for step: int in range(40):
		for pawn: Node3D in _pawns:
			pawn._process(0.05)
	for distance: float in DISTANCES:
		_camera.position = Vector3(0.0, EYE, -distance)
		_camera.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
		for moment: Dictionary in MOMENTS:
			await _shoot(moment, distance)
	for pawn: Node3D in _pawns:
		pawn.free()
	_viewport.free()
	await process_frame
	if not _failures.is_empty():
		for failure: String in _failures:
			push_error("union_tell_review: " + failure)
		quit(1)
		return
	print("union_tell_review: PASS")
	quit(0)


func _stage() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280, 720)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var world: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("1a1d22")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("4a5058")
	environment.ambient_light_energy = 0.35
	world.environment = environment
	_viewport.add_child(world)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -150, 0)
	sun.light_color = Color("fff1dc")
	sun.light_energy = 0.45
	_viewport.add_child(sun)
	var ground: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(80.0, 80.0)
	ground.mesh = plane
	var concrete: StandardMaterial3D = StandardMaterial3D.new()
	concrete.albedo_color = Color("4a4640")
	concrete.roughness = 1.0
	ground.material_override = concrete
	ground.position = Vector3(0, 0, 20)
	ground.layers = ArenaSky.WORLD_LAYERS
	_viewport.add_child(ground)
	var wall: MeshInstance3D = MeshInstance3D.new()
	var slab: BoxMesh = BoxMesh.new()
	slab.size = Vector3(80.0, 8.0, 0.5)
	wall.mesh = slab
	var plaster: StandardMaterial3D = StandardMaterial3D.new()
	plaster.albedo_color = Color("5c5e57")
	plaster.roughness = 1.0
	wall.material_override = plaster
	wall.position = Vector3(0, 4.0, 4.0)
	wall.layers = ArenaSky.WORLD_LAYERS
	_viewport.add_child(wall)
	_camera = Camera3D.new()
	_camera.fov = 75.0
	_camera.near = 0.05
	_camera.far = 200.0
	_viewport.add_child(_camera)
	_camera.make_current()


func _state(index: int, phase: String, started: int, ends: int) -> Dictionary:
	var kind: String = KINDS[index]
	# The camera looks down +Z, so screen left is +X: the first subject stands there.
	var x: float = (float(KINDS.size() - 1) * 0.5 - float(index)) * SPACING
	return {"id": "union-" + kind, "name": kind, "x": x, "y": FEET, "z": 0.0,
		"yaw": -PI * 0.5, "hp": 100, "weapon": WEAPONS[kind], "ducking": false,
		"campaign": {"side": "union", "kind": kind, "phase": phase,
			"phase_started": started, "phase_ends": ends}}


func _subject(index: int) -> Node3D:
	var pawn: Node3D = load("res://scenes/player.tscn").instantiate() as Node3D
	_viewport.add_child(pawn)
	pawn.set_process(false)
	pawn.nameplate_enabled = false
	pawn.set_player_data("union-" + KINDS[index], KINDS[index])
	pawn.update_state(_state(index, "moving", 1, 1), _tick)
	pawn.snap_authoritative_position()
	pawn.set_nameplate_enabled(false)
	return pawn


func _shoot(moment: Dictionary, distance: float) -> void:
	# A fresh authoritative tick for every photograph, with no extrapolation:
	# the frame shows exactly the tick the moment names.
	_tick += 50
	var started: int = _tick - int(moment["age"])
	for index: int in range(_pawns.size()):
		var pawn: Node3D = _pawns[index]
		pawn.update_state(_state(index, str(moment["phase"]), started, started + int(moment["length"])), _tick)
		pawn._process(0.0)
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var picture: Image = _viewport.get_texture().get_image()
	if picture == null or picture.is_empty():
		_failures.append("frame %s %d m" % [moment["label"], int(distance)])
		return
	picture.convert(Image.FORMAT_RGB8)
	var label: String = "tell_%02dm_%s" % [int(distance), moment["label"]]
	if picture.save_png(_out.path_join(label + ".png")) != OK:
		_failures.append("saved " + label)
	if distance > 10.0:
		var metre: float = 720.0 / (2.0 * distance * tan(deg_to_rad(37.5)))
		var width: int = mini(int(SPACING * float(KINDS.size()) * metre) + 24, 1280)
		var height: int = int(2.4 * metre) + 12
		var crop: Image = picture.get_region(Rect2i(640 - width / 2, 360 - height / 2 - 4, width, height))
		var zoom: int = clampi(1700 / width, 1, 4)
		crop.resize(width * zoom, height * zoom, Image.INTERPOLATE_NEAREST)
		if crop.save_png(_out.path_join(label + "_zoom.png")) != OK:
			_failures.append("saved zoom " + label)
