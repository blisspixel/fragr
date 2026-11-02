extends SceneTree

## Fighter roster lineup: every look on the actual pawn, sideless with its
## personal accent, then a coalition and a Union side of mixed looks, under a
## bright and a dim light at 6 and 15 metres, in colour and grayscale.
## Controlled presentation fixtures with no network play or outcome
## authority; the snapshot shapes are the wire's (`body`, `dress`, `team`).
##
## Usage: godot --path client --script res://qa/roster_review.gd -- /abs/out
const DISTANCES: Array[float] = [3.5, 6.0, 15.0]
const SPACING: float = 1.25
const EYE: float = 1.6
const FEET: float = 1.5
const GROUPS: Dictionary[String, Array] = {
	"humans": [
		{"body": "human", "look": 0, "accent": 0}, {"body": "human", "look": 1, "accent": 1},
		{"body": "human", "look": 2, "accent": 3}, {"body": "human", "look": 3, "accent": 4},
		{"body": "human", "look": 4, "accent": 2}, {"body": "human", "look": 5, "accent": 5},
		{"body": "human", "look": 6, "accent": 6}, {"body": "human", "look": 7, "accent": 7},
	],
	"agents": [
		{"body": "synthetic", "look": 0, "accent": 3}, {"body": "synthetic", "look": 1, "accent": 0},
		{"body": "synthetic", "look": 2, "accent": 4}, {"body": "synthetic", "look": 3, "accent": 1},
		{"body": "synthetic", "look": 4, "accent": 2},
	],
	"sides": [
		{"body": "human", "look": 2, "accent": 3, "team": "coalition"},
		{"body": "synthetic", "look": 3, "accent": 1, "team": "coalition"},
		{"body": "human", "look": 5, "accent": 6, "team": "coalition"},
		{"body": "human", "look": 0, "accent": 0, "team": "union"},
		{"body": "human", "look": 1, "accent": 3, "team": "union"},
		{"body": "synthetic", "look": 2, "accent": 4, "team": "union"},
		{"body": "human", "look": 7, "accent": 5, "team": "union"},
	],
}

var _viewport: SubViewport
var _camera: Camera3D
var _environment: Environment
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
var _out: String
var _failures: PackedStringArray = []
var _rows: Array[Dictionary] = []


func _initialize() -> void:
	set_meta("localexception_automated", true)
	set_meta("localexception_settings_path", "")
	set_meta("localexception_records_path", "")
	call_deferred("_run")


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1 or not args[0].is_absolute_path() or DirAccess.make_dir_recursive_absolute(args[0]) != OK:
		push_error("roster_review: require absolute output directory")
		quit(1)
		return
	_out = args[0]
	AudioServer.set_bus_mute(0, true)
	_stage()
	for group: String in GROUPS:
		var pawns: Array[Node3D] = []
		var subjects: Array = GROUPS[group]
		for index: int in range(subjects.size()):
			pawns.append(_subject(subjects[index], index, subjects.size()))
		for lighting: String in ["bright", "dim"]:
			_light(lighting)
			for distance: float in DISTANCES:
				await _shoot(pawns, "%s_%s_%02dm" % [group, lighting, int(distance)], distance, subjects.size())
		for pawn: Node3D in pawns:
			pawn.free()
	var file: FileAccess = FileAccess.open(_out.path_join("review.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"schema": 1,
			"scope": "Controlled lineup of actual pawns; no network play or outcome authority",
			"renderer": RenderingServer.get_current_rendering_method(),
			"groups": GROUPS, "frames": _rows, "failures": _failures}, "\t") + "\n")
		file.close()
	_viewport.free()
	await process_frame
	if not _failures.is_empty():
		for failure: String in _failures:
			push_error("roster_review: " + failure)
		quit(1)
		return
	print("roster_review: PASS (%d frames)" % _rows.size())
	quit(0)


func _stage() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280, 720)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var world: WorldEnvironment = WorldEnvironment.new()
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment = _environment
	_viewport.add_child(world)
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-40, -150, 0)
	_sun.shadow_enabled = true
	_viewport.add_child(_sun)
	_fill = DirectionalLight3D.new()
	_fill.rotation_degrees = Vector3(-15, 30, 0)
	_viewport.add_child(_fill)
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


## The same bright exterior and dim interior as the faction lineup.
func _light(lighting: String) -> void:
	var bright: bool = lighting == "bright"
	_environment.background_color = Color("8a96a0") if bright else Color("1a1d22")
	_environment.ambient_light_color = Color("b8bcc0") if bright else Color("4a5058")
	_environment.ambient_light_energy = 0.6 if bright else 0.35
	_sun.light_color = Color("fff1dc")
	_sun.light_energy = 1.3 if bright else 0.45
	_fill.light_color = Color("c8d4e0")
	_fill.light_energy = 0.35 if bright else 0.18


func _subject(subject: Dictionary, index: int, count: int) -> Node3D:
	var pawn: Node3D = load("res://scenes/player.tscn").instantiate() as Node3D
	_viewport.add_child(pawn)
	pawn.set_process(false)
	pawn.nameplate_enabled = false
	var id: String = "%s-%d-%d" % [subject["body"], subject["look"], index]
	pawn.set_player_data(id, id)
	var x: float = (float(count - 1) * 0.5 - float(index)) * SPACING
	var state: Dictionary = {"id": id, "name": id, "x": x, "y": FEET, "z": 0.0, "yaw": -PI * 0.5,
		"hp": 100, "weapon": "Tack", "ducking": false, "body": subject["body"],
		"dress": {"look": subject["look"], "accent": subject["accent"]}}
	if subject.has("team"):
		state["team"] = subject["team"]
	pawn.update_state(state, 1)
	pawn.snap_authoritative_position()
	pawn.set_nameplate_enabled(false)
	var view: SkinnedCharacter = pawn.character_view
	_expect(view != null, "live body for " + id)
	if view == null:
		return pawn
	var union: bool = subject.get("team", "") == "union"
	# The Union side wears issued livery from the own art, never the look.
	var expected: Texture2D = null if union else FighterLooks.texture(str(subject["body"]), int(subject["look"]))
	_expect(FighterLooks.worn(view) == expected, "%s wears its look, or issue on the Union side" % id)
	_expect(view.livery == ("union" if union else "free"), "%s livery follows its side" % id)
	var band: Array[Node] = view.find_children("PersonalBand", "MeshInstance3D", true, false)
	_expect(band.size() == 1 and (band[0] as MeshInstance3D).visible == not union,
		"%s personal band shows only on the free side" % id)
	var all_seals: Array[Node] = view.find_children("RankSeal", "MeshInstance3D", true, false)
	var seals: int = all_seals.filter(func(seal: Node) -> bool: return (seal as MeshInstance3D).visible).size()
	var rank: int = FighterLooks.union_rank(int(subject["look"])) if union else 0
	_expect(all_seals.size() == 3 and seals == [0, 1, all_seals.size()][rank],
		"%s rank seals follow Union rank" % id)
	return pawn


func _shoot(pawns: Array[Node3D], label: String, distance: float, count: int) -> void:
	_camera.position = Vector3(0.0, EYE, -distance)
	_camera.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
	for step: int in range(20):
		for pawn: Node3D in pawns:
			pawn._process(0.05)
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var picture: Image = _viewport.get_texture().get_image()
	if picture == null or picture.is_empty():
		_expect(false, "frame " + label)
		return
	picture.convert(Image.FORMAT_RGB8)
	_save(picture, label)
	var gray: Image = picture.duplicate() as Image
	gray.adjust_bcs(1.0, 1.0, 0.0)
	_save(gray, label + "_gray")
	if distance > 10.0:
		# The lineup at its true pixels, enlarged without filtering.
		var metre: float = 720.0 / (2.0 * distance * tan(deg_to_rad(37.5)))
		var width: int = mini(int(SPACING * float(count + 1) * metre) + 24, 1280)
		var height: int = int(2.4 * metre) + 12
		var region: Rect2i = Rect2i(640 - width / 2, 360 - height / 2 - 4, width, height)
		var crop: Image = picture.get_region(region)
		var zoom: int = clampi(1700 / width, 1, 4)
		crop.resize(width * zoom, height * zoom, Image.INTERPOLATE_NEAREST)
		_save(crop, label + "_zoom")


func _save(image: Image, label: String) -> void:
	var path: String = _out.path_join(label + ".png")
	_expect(image.save_png(path) == OK, "saved " + label)
	_rows.append({"file": label + ".png", "sha256": FileAccess.get_sha256(path)})


func _expect(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)
