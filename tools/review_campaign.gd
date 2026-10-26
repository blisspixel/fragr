extends "audit_world_signs.gd"

## Reconstruct the survey's recorded four-second scene windows. This uses real
## world, fighter and shot presenters, but is not an ordinary client session.
## Run with a renderer, --path client --script ../tools/review_campaign.gd --
## /absolute/report.json /absolute/output-directory
const PAWN: PackedScene = preload("res://scenes/player.tscn")
const STEP: float = 0.05

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2:
		_fail("campaign review needs report.json and an output directory")
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not parsed is Dictionary or parsed.get("schema") != 1:
		_fail("invalid campaign report")
		return
	var reviews: Array[Dictionary] = []
	for key: String in ["first_kill_review", "review"]:
		var item: Variant = parsed.get(key)
		if item == null:
			continue
		if not _valid_review(item):
			_fail("invalid recorded scene: " + key)
			return
		reviews.append(item)
	if reviews.is_empty():
		_fail("report has no recorded scene windows")
		return
	if not _renderer_ready():
		return
	if not args[1].is_absolute_path() or DirAccess.make_dir_recursive_absolute(args[1]) != OK:
		_fail("cannot create absolute output directory")
		return
	for review: Dictionary in reviews:
		if not await _render_review(review, args[1]):
			Engine.time_scale = 1.0
			return
	Engine.time_scale = 1.0
	await create_timer(0.1).timeout
	print("campaign review: PASS ", reviews.size(), " reconstructed scene windows")
	quit(0)

static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func _valid_review(value: Variant) -> bool:
	if not value is Dictionary or not value.get("map_info") is Dictionary \
			or not value.get("view") is Dictionary or not value.get("frames") is Array:
		return false
	if not value.get("event") in ["first_kill", "fatal_hit"] or not value["view"].get("id") is String:
		return false
	if not MapGeometry.validation_error(value["map_info"]).is_empty():
		return false
	var frames: Array = value["frames"]
	if frames.is_empty() or frames.size() > 80:
		return false
	var previous: int = -1
	for frame: Variant in frames:
		if not frame is Dictionary or not EquipmentState.integer(frame.get("tick"), EquipmentState.MAX_EXACT_INTEGER) or not frame.get("players") is Array:
			return false
		if not ActorState.validation_error(frame).is_empty():
			return false
		var tick: int = int(frame["tick"])
		if tick < 0 or (previous >= 0 and tick != previous + 1) or frame["players"].size() > 64:
			return false
		previous = tick
		var viewer_found: bool = false
		for player: Variant in frame["players"]:
			if not player is Dictionary or not player.get("id") is String or not player.get("weapon") is String:
				return false
			for key: String in ["x", "y", "z", "yaw", "pitch", "hp"]:
				if not _number(player.get(key)) or absf(float(player[key])) > 8192.0:
					return false
			viewer_found = viewer_found or player["id"] == value["view"]["id"]
		if not viewer_found or not frame.get("shot_results", []) is Array:
			return false
	return true

func _render_review(review: Dictionary, out: String) -> bool:
	var info: Dictionary = review["map_info"]
	var directory: String = out.path_join(str(review["event"]))
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		_fail("cannot create scene output")
		return false
	var arena: Node3D = _build(info)
	_freeze_stage(arena)
	var camera: Camera3D = _setup_view(arena, str(info.get("map_name", "Recall Notice")))
	var shots: ShotEffects = ShotEffects.new()
	arena.add_child(shots)
	shots.decals = VfxDecals.new()
	arena.add_child(shots.decals)
	shots.configure_map(info)
	var pawns: Dictionary[String, Node3D] = {}
	shots.fighter_surface = func(id: String) -> String:
		return str(pawns[id].call("impact_surface")) if pawns.has(id) else ShotVfx.FLESH
	var flashes: Dictionary[String, float] = {}
	var index: int = 0
	for frame: Dictionary in review["frames"]:
		for id: String in flashes.keys():
			flashes[id] -= STEP
			if flashes[id] <= 0.0:
				if pawns.has(id):
					_hide_flash(pawns[id])
				flashes.erase(id)
		var present: Array[String] = []
		for data: Dictionary in frame["players"]:
			var id: String = str(data["id"])
			if id == review["view"]["id"]:
				var yaw: float = float(data["yaw"])
				var pitch: float = float(data["pitch"])
				camera.position = Vector3(float(data["x"]), float(data["y"]) - 1.5 + 1.6, float(data["z"]))
				camera.look_at(camera.position + Vector3(cos(yaw) * cos(pitch), sin(pitch), sin(yaw) * cos(pitch)))
				continue
			present.append(id)
			if not pawns.has(id):
				pawns[id] = PAWN.instantiate()
				arena.add_child(pawns[id])
				pawns[id].call("set_player_data", id, str(data.get("name", "")))
				pawns[id].call("set_nameplate_enabled", false)
				pawns[id].position = Vector3(float(data["x"]), float(data["y"]), float(data["z"]))
			_step_pawn(pawns[id], data, int(frame["tick"]))
		for id: String in pawns.keys():
			if not id in present:
				pawns[id].queue_free()
				pawns.erase(id)
		shots.call("_process", STEP)
		shots.decals.call("_process", STEP)
		shots.ingest(int(frame["tick"]), frame.get("shot_results", []))
		var fired: Dictionary[String, bool] = {}
		for shot: Variant in frame.get("shot_results", []):
			if not shot is Dictionary or not shot.get("shooter_id") is String:
				continue
			var shooter: String = shot["shooter_id"]
			if not pawns.has(shooter) or fired.has(shooter):
				continue
			fired[shooter] = true
			var pawn: Node3D = pawns[shooter]
			var weapon: String = str(pawn.call("get_weapon_name"))
			var trace: Variant = shot.get("trace")
			if trace is Dictionary and trace.get("weapon") in EquipmentState.WEAPONS:
				weapon = str(trace["weapon"]).capitalize()
			flashes[shooter] = _start_flash(pawn, weapon)
			# Render the newly acknowledged firing pose at age zero.
			pawn.call("_process", 0.0)
		# Initial assets need several frames; subsequent snapshots advance at the
		# report's 20 Hz when the saved images are assembled at 20 frames/second.
		for settle: int in range(16 if index == 0 else 1):
			await process_frame
		await RenderingServer.frame_post_draw
		if root.get_texture().get_image().save_png(directory.path_join("%04d.png" % index)) != OK:
			_fail("cannot save recorded frame")
			return false
		index += 1
	arena.queue_free()
	for settle: int in range(4):
		await process_frame
	print("campaign review: ", review["event"], " ", index, " frames")
	return true

static func _freeze_stage(arena: Node3D) -> void:
	# Match combat_vfx_review: asynchronous muzzle timers, automatic pawn
	# updates and render duration must not age recorded effects.
	Engine.time_scale = 0.0
	arena.process_mode = Node.PROCESS_MODE_DISABLED

static func _hide_flash(pawn: Node3D) -> void:
	var muzzle: Sprite3D = pawn.get("muzzle") as Sprite3D
	var glow: OmniLight3D = pawn.get("muzzle_glow") as OmniLight3D
	if muzzle != null:
		muzzle.visible = false
		muzzle.scale = Vector3.ONE
	if glow != null:
		glow.light_energy = 0.0

static func _start_flash(pawn: Node3D, weapon: String) -> float:
	pawn.call("show_muzzle_flash", weapon)
	# Keep the normal pose, texture and light, but retire its asynchronous
	# expiry token. Only the recorded clock below may end this flash.
	pawn.set("_fire_feedback_revision", int(pawn.get("_fire_feedback_revision")) + 1)
	return float(ShotVfx.muzzle_look(weapon)["seconds"])

static func _step_pawn(pawn: Node3D, data: Dictionary, tick: int) -> void:
	var at: Vector3 = Vector3(float(data["x"]), float(data["y"]), float(data["z"]))
	var distance: float = Vector2(at.x - pawn.position.x, at.z - pawn.position.z).length()
	# The existing prediction presentation branch accepts exact positions and
	# facing. Leave the previous position until _process measures its travel,
	# so the ordinary enemy presenter advances its gait instead of sliding.
	pawn.set("prediction_active", true)
	pawn.set("predicted_position", at)
	pawn.set("predicted_speed", distance / STEP)
	pawn.call("update_state", data, tick)
	pawn.call("set_ducking", data.get("ducking") == true)
	pawn.call("_process", STEP)
