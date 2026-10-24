extends SceneTree

## Faction readability lineup: the actual pawns, side by side, photographed at
## 5, 15 and 30 metres under a bright and a dim light, in colour and in
## grayscale, then once more under the bright light with spectator nameplates
## and their team edges. Controlled presentation fixtures with no network play or
## outcome authority. No Inheritance machine exists in the client yet, so the
## lineup holds free bodies (sideless, free coalition) and the Union (a free
## body on the Union side of a team match, and two campaign Union actors).
##
## Usage: godot --path client --script res://qa/faction_readability_review.gd -- /abs/out
const DISTANCES: Array[float] = [5.0, 15.0, 30.0]
const SPACING: float = 1.6
const EYE: float = 1.6
## Pawns stand with their feet 1.5 m below the server reference.
const FEET: float = 1.5
const SUBJECTS: Array[Dictionary] = [
	{"id": "ffa-human", "name": "Nightfall", "body": "human", "team": ""},
	{"id": "ffa-synthetic", "name": "Static Kid", "body": "synthetic", "team": ""},
	{"id": "free-human", "name": "Aunt Linda", "body": "human", "team": "coalition"},
	{"id": "free-synthetic", "name": "Crackpot", "body": "synthetic", "team": "coalition"},
	{"id": "union-synthetic", "name": "Buzzkill", "body": "synthetic", "team": "union"},
	{"id": "union-human", "name": "Scout Ant", "body": "human", "team": "union"},
	{"id": "union-sweeper", "name": "sweeper-1", "campaign": "sweeper"},
	{"id": "union-clerk", "name": "clerk-1", "campaign": "clerk"},
]
## The nameplate pass: one participant of each kind of side, spaced per
## distance so their plates, which grow with range, never overlap.
const PLATE_SUBJECTS: Array[String] = ["ffa-human", "free-human", "free-synthetic", "union-human"]
const PLATE_SPACING: Dictionary[float, float] = {15.0: 10.0, 30.0: 15.0}

var _viewport: SubViewport
var _camera: Camera3D
var _environment: Environment
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
var _out: String
var _pawns: Array[Node3D] = []
var _states: Array[Dictionary] = []
var _failures: PackedStringArray = []
var _rows: Array[Dictionary] = []


func _initialize() -> void:
	set_meta("fragr_automated", true)
	set_meta("fragr_settings_path", "")
	set_meta("fragr_records_path", "")
	call_deferred("_run")


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1 or not args[0].is_absolute_path() or DirAccess.make_dir_recursive_absolute(args[0]) != OK:
		push_error("faction_readability_review: require absolute output directory")
		quit(1)
		return
	_out = args[0]
	AudioServer.set_bus_mute(0, true)
	_stage()
	for index: int in range(SUBJECTS.size()):
		_pawns.append(_subject(SUBJECTS[index], index))
	for lighting: String in ["bright", "dim"]:
		_light(lighting)
		for distance: float in DISTANCES:
			await _shoot(lighting, distance)
	# The team overlay: one fighter of each kind of side, spread apart so their
	# spectator plates and side edges (solid Union bar, open free frame) do not
	# overlap, at the two distances a plate must still be read.
	_light("bright")
	var tick: int = 2
	for distance: float in PLATE_SPACING:
		var spacing: float = PLATE_SPACING[distance]
		var shown: int = 0
		for index: int in range(SUBJECTS.size()):
			var pawn: Node3D = _pawns[index]
			pawn.visible = PLATE_SUBJECTS.has(SUBJECTS[index]["id"])
			if not pawn.visible:
				continue
			var state: Dictionary = _states[index]
			state["x"] = (float(PLATE_SUBJECTS.size() - 1) * 0.5 - float(shown)) * spacing
			pawn.update_state(state, tick)
			pawn.snap_authoritative_position()
			pawn.set_nameplate_enabled(true)
			var edge: Node3D = pawn.get_node_or_null("Label3D/PlateEdge") as Node3D
			var sided: bool = not str(SUBJECTS[index].get("team", "")).is_empty()
			_expect((edge != null and edge.visible) == sided, "%s plate edge follows its side" % SUBJECTS[index]["id"])
			shown += 1
		tick += 1
		await _shoot("plates", distance, spacing, PLATE_SUBJECTS.size())
	var file: FileAccess = FileAccess.open(_out.path_join("review.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"schema": 1,
			"scope": "Controlled lineup of actual pawns; no network play or outcome authority",
			"renderer": RenderingServer.get_current_rendering_method(),
			"video_adapter": RenderingServer.get_video_adapter_name(),
			"subjects": SUBJECTS, "frames": _rows, "failures": _failures}, "\t") + "\n")
		file.close()
	for pawn: Node3D in _pawns:
		pawn.free()
	_viewport.free()
	await process_frame
	if not _failures.is_empty():
		for failure: String in _failures:
			push_error("faction_readability_review: " + failure)
		quit(1)
		return
	print("faction_readability_review: PASS (%d frames)" % _rows.size())
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


## A bright exterior and a dim interior with a cool fill, the two combat
## conditions the contract asks every band to survive.
func _light(lighting: String) -> void:
	var bright: bool = lighting == "bright"
	_environment.background_color = Color("8a96a0") if bright else Color("1a1d22")
	_environment.ambient_light_color = Color("b8bcc0") if bright else Color("4a5058")
	_environment.ambient_light_energy = 0.6 if bright else 0.35
	_sun.light_color = Color("fff1dc")
	_sun.light_energy = 1.3 if bright else 0.45
	_fill.light_color = Color("c8d4e0")
	_fill.light_energy = 0.35 if bright else 0.18


func _subject(subject: Dictionary, index: int) -> Node3D:
	var pawn: Node3D = load("res://scenes/player.tscn").instantiate() as Node3D
	_viewport.add_child(pawn)
	pawn.set_process(false)
	pawn.nameplate_enabled = false
	pawn.set_player_data(str(subject["id"]), str(subject["name"]))
	# The camera looks down +Z, so screen left is +X: the first subject stands there.
	var x: float = (float(SUBJECTS.size() - 1) * 0.5 - float(index)) * SPACING
	# The figures face the camera, which stands on -Z.
	var state: Dictionary = {"id": subject["id"], "name": subject["name"], "x": x, "y": FEET, "z": 0.0,
		"yaw": -PI * 0.5, "hp": 100, "weapon": "Tack", "ducking": false}
	if subject.has("campaign"):
		state["campaign"] = {"side": "union", "kind": subject["campaign"], "phase": "idle",
			"phase_started": 1, "phase_ends": 1}
	else:
		state["body"] = subject["body"]
		if not str(subject["team"]).is_empty():
			state["team"] = subject["team"]
	_states.append(state)
	pawn.update_state(state, 1)
	pawn.snap_authoritative_position()
	pawn.set_nameplate_enabled(false)
	if not subject.has("campaign"):
		_expect(pawn.character_view != null, "live body for " + str(subject["id"]))
		if pawn.character_view != null:
			var expected: String = "union" if subject["team"] == "union" else "free"
			_expect(pawn.character_view.livery == expected, "%s wears %s livery" % [subject["id"], expected])
			_expect(str(pawn.body_scheme_note).is_empty() or subject["team"] == "",
				"%s side accent passes as chosen" % subject["id"])
	return pawn


func _shoot(lighting: String, distance: float, spacing: float = SPACING, count: int = SUBJECTS.size()) -> void:
	_camera.position = Vector3(0.0, EYE, -distance)
	_camera.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
	# Campaign actors ease toward their accepted facing; let them arrive.
	for step: int in range(40):
		for pawn: Node3D in _pawns:
			pawn._process(0.05)
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var picture: Image = _viewport.get_texture().get_image()
	if picture == null or picture.is_empty():
		_expect(false, "frame %s %d m" % [lighting, int(distance)])
		return
	picture.convert(Image.FORMAT_RGB8)
	var label: String = "lineup_%s_%02dm" % [lighting, int(distance)]
	_save(picture, label)
	var gray: Image = picture.duplicate() as Image
	gray.adjust_bcs(1.0, 1.0, 0.0)
	_save(gray, label + "_gray")
	if distance > 10.0:
		# The lineup at its true pixels, enlarged without filtering, so the
		# reviewer sees what the player's screen holds at that range.
		var metre: float = 720.0 / (2.0 * distance * tan(deg_to_rad(37.5)))
		# Plates are wider than the figures under them, so their crop is too.
		var span: float = spacing * float(count + (1 if lighting == "plates" else 0))
		var width: int = mini(int(span * metre) + 24, 1280)
		# Plates stand over the heads, so their crop is taller.
		var tall: float = 2.4 if lighting != "plates" else 4.0
		var height: int = int(tall * metre) + 12
		var region: Rect2i = Rect2i(640 - width / 2, 360 - height / 2 - 4 - (0 if lighting != "plates" else int(0.8 * metre)), width, height)
		for pair: Array in [[picture, ""], [gray, "_gray"]]:
			var crop: Image = (pair[0] as Image).get_region(region)
			var zoom: int = clampi(1700 / width, 1, 4)
			crop.resize(width * zoom, height * zoom, Image.INTERPOLATE_NEAREST)
			_save(crop, label + "_zoom" + str(pair[1]))


func _save(image: Image, label: String) -> void:
	var path: String = _out.path_join(label + ".png")
	_expect(image.save_png(path) == OK, "saved " + label)
	_rows.append({"file": label + ".png", "sha256": FileAccess.get_sha256(path)})


func _expect(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)
