extends "audit_world_signs.gd"

## Reconstruct the survey's recorded four-second scene windows. This uses real
## world, fighter and shot presenters, but is not an ordinary client session.
## Run with a renderer, --path client --script ../tools/review_campaign.gd --
## /absolute/report.json /absolute/output-directory
const PAWN: PackedScene = preload("res://scenes/player.tscn")

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
			return
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
	var frames: Array = value["frames"]
	if frames.is_empty() or frames.size() > 80:
		return false
	var previous: int = -1
	for frame: Variant in frames:
		if not frame is Dictionary or not _number(frame.get("tick")) or not frame.get("players") is Array:
			return false
		var tick: int = int(frame["tick"])
		if tick < 0 or (previous >= 0 and tick != previous + 1) or frame["players"].size() > 64:
			return false
		previous = tick
		var viewer_found: bool = false
		for player: Variant in frame["players"]:
			if not player is Dictionary or not player.get("id") is String:
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
	var camera: Camera3D = _setup_view(arena, str(info.get("map_name", "Recall Notice")))
	var shots: ShotEffects = ShotEffects.new()
	arena.add_child(shots)
	shots.configure_map(info)
	shots.set_process(false)
	var pawns: Dictionary[String, Node3D] = {}
	var index: int = 0
	for frame: Dictionary in review["frames"]:
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
			pawns[id].call("update_state", data, int(frame["tick"]))
			pawns[id].position = Vector3(float(data["x"]), float(data["y"]), float(data["z"]))
		for id: String in pawns.keys():
			if not id in present:
				pawns[id].queue_free()
				pawns.erase(id)
		shots.call("_process", 0.05)
		shots.ingest(int(frame["tick"]), frame.get("shot_results", []))
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
