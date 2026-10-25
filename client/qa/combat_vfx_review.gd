extends SceneTree

## Combat effects lineup on a small authored range with registered materials:
## a blast against a concrete wall played frame by frame, a rocket flying and
## striking a steel pillar, one Rifle round into concrete, steel, a human and
## a free agent's synthetic body, the Railgun from the shooter's own eye and
## from the side, and every gun's third-person flash and light. Engine time
## is held still and each effect is stepped by hand, so every frame shows an
## exact age. Controlled presentation fixtures with no network play or
## outcome authority; the live tour (`res://qa/combat-vfx.json`) is the
## in-match check.
##
## Usage: godot --path client --script res://qa/combat_vfx_review.gd -- /abs/out
const OWNER: String = "00000000-0000-4000-8000-0000000000aa"
const SIZE: Vector2i = Vector2i(1280, 720)
const BLAST_TIMES: Array[float] = [0.02, 0.06, 0.12, 0.2, 0.3, 0.42, 0.6, 0.9, 1.4, 2.2]
const IMPACT_TIMES: Array[float] = [0.01, 0.06, 0.11, 0.16, 0.21, 0.27]
const RAIL_TIMES: Array[float] = [0.01, 0.06, 0.14, 0.26, 0.4, 0.56]
const GUNS: Array[String] = ["Tack", "Flechette", "Repeater", "Scatter", "Rail", "Sniper", "Rocket", "Arc"]

var _viewport: SubViewport
var _camera: Camera3D
var _out: String
var _failures: PackedStringArray = []
var _shots: ShotEffects
var _effects: GrenadeEffects
var _decals: VfxDecals
var _tick: int = 100


func _initialize() -> void:
	set_meta("fragr_automated", true)
	set_meta("fragr_settings_path", "")
	set_meta("fragr_records_path", "")
	call_deferred("_run")


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1 or not args[0].is_absolute_path() or DirAccess.make_dir_recursive_absolute(args[0]) != OK:
		push_error("combat_vfx_review: require absolute output directory")
		quit(1)
		return
	_out = args[0]
	AudioServer.set_bus_mute(0, true)
	# Hold engine time: every effect is stepped explicitly below.
	Engine.time_scale = 0.0
	_stage()
	await _blast_series()
	await _rocket_series()
	await _impact_series()
	await _rail_series()
	await _muzzle_series()
	Engine.time_scale = 1.0
	_viewport.free()
	# Let freed render resources retire before the engine counts them.
	for _frame: int in range(4):
		await process_frame
	if not _failures.is_empty():
		for failure: String in _failures:
			push_error("combat_vfx_review: " + failure)
		quit(1)
		return
	print("combat_vfx_review: PASS ", _out)
	quit(0)


func _map() -> Dictionary:
	var solids: Array = []
	var kits: Array = []
	var add: Callable = func(x: Vector2, z: Vector2, top: float, kit: String) -> void:
		solids.append({"min_x": x.x, "max_x": x.y, "min_z": z.x, "max_z": z.y, "bottom": 0.0, "top": top})
		kits.append(kit)
	add.call(Vector2(-14.0, 14.0), Vector2(8.0, 9.0), 6.0, "concrete")
	add.call(Vector2(6.0, 7.0), Vector2(2.0, 4.0), 4.0, "service_steel")
	add.call(Vector2(-4.5, -3.5), Vector2(4.5, 5.5), 2.5, "concrete")
	add.call(Vector2(-1.5, -0.5), Vector2(4.5, 5.5), 2.5, "service_steel")
	add.call(Vector2(-9.0, -7.0), Vector2(2.0, 4.0), 3.0, "enamel")
	return {"map_id": 9001, "map_name": "Effects Range", "half_extent": 30.0, "geometry_version": 2,
		"solids": solids, "presentation": {"ground": "concrete", "solids": kits, "decorations": []}}


func _stage() -> void:
	_viewport = SubViewport.new()
	_viewport.size = SIZE
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var world: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("221c26")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("5a5660")
	environment.ambient_light_energy = 0.4
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = environment
	_viewport.add_child(world)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -150, 0)
	sun.light_color = Color("f2c79a")
	sun.light_energy = 0.35
	_viewport.add_child(sun)
	var info: Dictionary = _map()
	var cover: ArenaCover = ArenaCover.new()
	cover.apply_map_info(info)
	_viewport.add_child(cover)
	_decals = VfxDecals.new()
	_viewport.add_child(_decals)
	_decals.set_map(info)
	_shots = ShotEffects.new()
	_viewport.add_child(_shots)
	_shots.decals = _decals
	_shots.fighter_surface = func(id: String) -> String:
		return ShotVfx.SYNTHETIC if id == "agent" else ShotVfx.FLESH
	_effects = GrenadeEffects.new()
	_viewport.add_child(_effects)
	_effects.set_decals(_decals)
	_effects.apply({"tick": 1}, Vector3.INF)
	_camera = Camera3D.new()
	_camera.fov = 75.0
	_camera.near = 0.05
	_camera.far = 200.0
	_viewport.add_child(_camera)
	_camera.make_current()


func _look(from: Vector3, at: Vector3) -> void:
	_camera.position = from
	_camera.look_at(at, Vector3.UP)


func _frame() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var picture: Image = _viewport.get_texture().get_image()
	if picture == null or picture.is_empty():
		_failures.append("empty frame")
		return Image.create_empty(SIZE.x, SIZE.y, false, Image.FORMAT_RGB8)
	picture.convert(Image.FORMAT_RGB8)
	return picture


func _save(picture: Image, label: String) -> void:
	if picture.save_png(_out.path_join(label + ".png")) != OK:
		_failures.append("saved " + label)


## Frames cropped to `region`, side by side, at `zoom`.
func _strip(frames: Array[Image], region: Rect2i, zoom: int, label: String) -> void:
	var strip: Image = Image.create_empty(region.size.x * zoom * frames.size(), region.size.y * zoom, false, Image.FORMAT_RGB8)
	for index: int in range(frames.size()):
		var crop: Image = frames[index].get_region(region)
		crop.resize(region.size.x * zoom, region.size.y * zoom, Image.INTERPOLATE_NEAREST)
		strip.blit_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), Vector2i(index * region.size.x * zoom, 0))
	_save(strip, label)


func _step_blast(delta: float) -> void:
	_effects._process(delta)
	_effects.blast.advance(delta)
	_effects.blast.fire.advance(delta)
	_effects.blast.smoke.advance(delta)
	_effects.blast.debris.advance(delta)
	_decals._process(delta)


func _clear() -> void:
	_shots.clear()
	_effects.reset()
	_effects.apply({"tick": _tick}, Vector3.INF)
	_tick += 1


func _blast_series() -> void:
	_clear()
	_look(Vector3(0.0, 1.7, 0.0), Vector3(2.0, 1.6, 8.0))
	_save(await _frame(), "blast_00_before")
	_effects.apply({"tick": _tick, "explosions": [{"id": 41, "owner_id": OWNER, "position": [2.5, 1.0, 7.9],
		"radius": 4, "hits": []}]}, Vector3.INF)
	_tick += 1
	var frames: Array[Image] = []
	var clock: float = 0.0
	for at: float in BLAST_TIMES:
		_step_blast(at - clock)
		clock = at
		var picture: Image = await _frame()
		frames.append(picture)
		_save(picture, "blast_%02d_%03dms" % [frames.size(), int(at * 1000.0)])
	_strip(frames.slice(0, 5), Rect2i(430, 110, 420, 420), 1, "blast_strip_a")
	_strip(frames.slice(5), Rect2i(430, 110, 420, 420), 1, "blast_strip_b")
	_step_blast(3.0)
	_save(await _frame(), "blast_scorch_after")
	if _decals.scorch_count() != 1:
		_failures.append("blast left %d scorches" % _decals.scorch_count())


func _rocket_series() -> void:
	_clear()
	_look(Vector3(1.0, 1.8, -1.5), Vector3(2.0, 1.5, 3.0))
	var frames: Array[Image] = []
	var start: Vector3 = Vector3(-9.0, 1.6, 3.0)
	var velocity: Vector3 = Vector3(18.0, 0.0, 0.0)
	var age: int = 0
	var position: Vector3 = start
	# Snapshots every tick, frames between them, until it reaches the pillar.
	while position.x < 5.9:
		_effects.apply({"tick": _tick, "players": [{"id": OWNER}], "rockets": [{"id": 77, "owner_id": OWNER,
			"position": [position.x, position.y, position.z], "velocity": [velocity.x, velocity.y, velocity.z],
			"age_ticks": age}]}, Vector3.INF)
		_tick += 1
		age += 1
		for half: int in range(2):
			_step_blast(0.025)
		if age % 2 == 0:
			var picture: Image = await _frame()
			frames.append(picture)
		position += velocity * 0.05
	_effects.apply({"tick": _tick, "players": [{"id": OWNER}], "explosions": [{"id": 78, "owner_id": OWNER,
		"position": [5.9, 1.6, 3.0], "radius": 4, "hits": []}]}, Vector3.INF)
	_tick += 1
	var clock: float = 0.0
	for at: float in [0.03, 0.1, 0.22, 0.4]:
		_step_blast(at - clock)
		clock = at
		frames.append(await _frame())
	for index: int in range(frames.size()):
		_save(frames[index], "rocket_%02d" % (index + 1))
	_strip(frames.slice(0, mini(frames.size(), 6)), Rect2i(0, 120, 1280, 420), 1, "rocket_strip_flight")


func _pawn(id: String, body: String, at: Vector3, yaw: float, weapon: String) -> Node3D:
	var pawn: Node3D = load("res://scenes/player.tscn").instantiate() as Node3D
	_viewport.add_child(pawn)
	pawn.set_process(false)
	pawn.nameplate_enabled = false
	pawn.set_player_data(id, id)
	var state: Dictionary = {"x": at.x, "y": at.y, "z": at.z, "yaw": yaw, "hp": 100, "weapon": weapon, "body": body}
	pawn.update_state(state, _tick)
	pawn.snap_authoritative_position()
	pawn.set_nameplate_enabled(false)
	pawn._process(0.05)
	return pawn


func _hit(weapon: String, origin: Vector3, end: Vector3, normal: Vector3, kind: String, target: String) -> Dictionary:
	var result: Dictionary = {"shooter_id": "review", "hit": kind == "fighter", "damage": 10,
		"trace": {"weapon": weapon, "origin": [origin.x, origin.y, origin.z], "end": [end.x, end.y, end.z],
			"impact": {"kind": kind, "normal": [normal.x, normal.y, normal.z]}}}
	if not target.is_empty():
		result["target_id"] = target
	return result


func _impact_series() -> void:
	_clear()
	var person: Node3D = _pawn("person", PlayerBody.HUMAN, Vector3(1.6, 1.5, 5.0), -PI * 0.5, "Flechette")
	var agent: Node3D = _pawn("agent", PlayerBody.SYNTHETIC, Vector3(4.0, 1.5, 5.0), -PI * 0.5, "Flechette")
	_look(Vector3(0.2, 1.6, 1.2), Vector3(0.2, 1.3, 5.0))
	var origin: Vector3 = Vector3(-6.0, 1.7, 0.0)
	var points: Array[Vector3] = [Vector3(-4.0, 1.3, 4.5), Vector3(-1.0, 1.3, 4.5), Vector3(1.6, 1.25, 4.75), Vector3(4.0, 1.25, 4.75)]
	_shots.ingest(_tick, [
		_hit("flechette", origin, points[0], Vector3.FORWARD, "solid", ""),
		_hit("flechette", origin, points[1], Vector3.FORWARD, "solid", ""),
		_hit("flechette", origin, points[2], Vector3(-0.2, 0.0, -1.0).normalized(), "fighter", "person"),
		_hit("flechette", origin, points[3], Vector3(-0.5, 0.0, -1.0).normalized(), "fighter", "agent")])
	_tick += 1
	var frames: Array[Image] = []
	var clock: float = 0.0
	for at: float in IMPACT_TIMES:
		_shots._process(at - clock)
		clock = at
		var picture: Image = await _frame()
		frames.append(picture)
		_save(picture, "impact_%02d_%03dms" % [frames.size(), int(at * 1000.0)])
	# One row per struck surface (concrete, steel, human, free agent), one
	# column per frame, each a zoomed crop round its hit.
	var cell: int = 96
	var zoom: int = 3
	var grid: Image = Image.create_empty(cell * zoom * frames.size(), cell * zoom * points.size(), false, Image.FORMAT_RGB8)
	for row: int in range(points.size()):
		var centre: Vector2 = _camera.unproject_position(points[row])
		var region: Rect2i = Rect2i(Vector2i(centre) - Vector2i(cell / 2, cell / 2), Vector2i(cell, cell))
		region.position = region.position.clamp(Vector2i.ZERO, SIZE - region.size)
		for column: int in range(frames.size()):
			var crop: Image = frames[column].get_region(region)
			crop.resize(cell * zoom, cell * zoom, Image.INTERPOLATE_NEAREST)
			grid.blit_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), Vector2i(column, row) * cell * zoom)
	_save(grid, "impact_grid")
	_shots._process(0.5)
	_save(await _frame(), "impact_marks_after")
	person.free()
	agent.free()


func _rail_series() -> void:
	_clear()
	# The shooter's own eye: the beam leaves the held gun, not the lens.
	var eye: Vector3 = Vector3(0.0, 1.6, -4.0)
	_look(eye, Vector3(0.6, 1.6, 8.0))
	_shots.ingest(_tick, [_hit("rail", eye, Vector3(0.6, 1.7, 8.0), Vector3(0, 0, -1), "solid", "")])
	_tick += 1
	var frames: Array[Image] = []
	var clock: float = 0.0
	for at: float in RAIL_TIMES:
		_shots._process(at - clock)
		clock = at
		var picture: Image = await _frame()
		frames.append(picture)
		_save(picture, "rail_fp_%02d_%03dms" % [frames.size(), int(at * 1000.0)])
	_strip(frames, Rect2i(0, 0, 1280, 720), 1, "rail_fp_strip")
	_clear()
	_look(Vector3(-7.0, 2.0, -1.0), Vector3(0.0, 1.4, 4.0))
	_shots.ingest(_tick, [_hit("rail", Vector3(-5.0, 1.6, -2.0), Vector3(5.0, 1.5, 7.95), Vector3(0, 0, -1), "solid", "")])
	_tick += 1
	frames.clear()
	clock = 0.0
	for at: float in RAIL_TIMES:
		_shots._process(at - clock)
		clock = at
		var picture: Image = await _frame()
		frames.append(picture)
		_save(picture, "rail_side_%02d_%03dms" % [frames.size(), int(at * 1000.0)])


func _muzzle_series() -> void:
	_clear()
	var pawns: Array[Node3D] = []
	for index: int in range(GUNS.size()):
		var x: float = (float(index) - float(GUNS.size() - 1) * 0.5) * 1.6
		pawns.append(_pawn("gun%d" % index, PlayerBody.HUMAN if index % 2 == 0 else PlayerBody.SYNTHETIC,
			Vector3(x, 1.5, 4.0), 0.0, GUNS[index]))
	_look(Vector3(0.0, 1.8, -3.5), Vector3(0.0, 1.3, 4.0))
	_save(await _frame(), "muzzle_rest")
	for index: int in range(pawns.size()):
		pawns[index].show_muzzle_flash(GUNS[index])
	_save(await _frame(), "muzzle_flash")
	# Let every flash finish its own timer before its pawn goes.
	Engine.time_scale = 1.0
	await create_timer(0.3).timeout
	for pawn: Node3D in pawns:
		pawn.free()
