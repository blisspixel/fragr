extends "res://scripts/qa_tour.gd"

## Ordinary inputs belong to the existing tour. This adds observations only.
var _assessor_samples: Array[Dictionary] = []
var _assessor_frames: Array[Dictionary] = []
var _assessor_last_tick: int = -1
var _assessor_last_frame_ms: int = -1000
var _assessor_capturing: bool = false

func _load_manifest() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://qa/assessor-foundation-development.json")) as Dictionary

func _process(delta: float) -> bool:
	super._process(delta)
	var game: Node = _game_manager()
	if game == null or paused or _assessor_samples.size() >= 4000:
		return false
	var snapshot: Dictionary = game.latest_snapshot
	var tick: int = int(snapshot.get("tick", -1))
	if tick <= _assessor_last_tick:
		return false
	_assessor_last_tick = tick
	var drone: Dictionary = {}
	for actor: Dictionary in snapshot.get("players", []):
		if actor.get("campaign", {}).get("kind") == "assessor":
			drone = actor.duplicate(true)
			break
	var canisters: Array = snapshot.get("assessor_canisters", []).duplicate(true)
	var explosions: Array = snapshot.get("explosions", []).duplicate(true)
	if drone.is_empty() and canisters.is_empty() and explosions.is_empty():
		return false
	_assessor_samples.append({"tick":tick,"drone":drone,"canisters":canisters,"explosions":explosions})
	if not _assessor_capturing and not canisters.is_empty() and _assessor_frames.size() < 48 \
		and Time.get_ticks_msec() - _assessor_last_frame_ms >= 100:
		_assessor_capturing = true
		_assessor_last_frame_ms = Time.get_ticks_msec()
		_capture_canister_frame.call_deferred()
	return false

func _capture_canister_frame() -> void:
	await RenderingServer.frame_post_draw
	var game: Node = _game_manager()
	if game != null and not _out_dir.is_empty():
		var snapshot: Dictionary = game.latest_snapshot
		var canisters: Array = snapshot.get("assessor_canisters", []).duplicate(true)
		if not canisters.is_empty():
			var filename: String = "canister_motion_%03d.png" % _assessor_frames.size()
			var frame: Image = _grab()
			if frame != null and frame.save_png(_out_dir.path_join(filename)) == OK:
				_assessor_frames.append({"file":filename,"tick":snapshot.tick,"canisters":canisters})
			else:
				_failed = true
	_assessor_capturing = false

func _write_manifest(tour: Dictionary) -> void:
	super._write_manifest(tour)
	var file: FileAccess = FileAccess.open(_out_dir.path_join("assessor-motion.json"), FileAccess.WRITE)
	if file == null:
		push_error("assessor_live_tour: cannot retain actual motion observations")
		_failed = true
		return
	file.store_string(JSON.stringify({"schema":1,"scope":"separate finite human development lesson",
		"observations_only":true,"rig_sha256":FileAccess.get_sha256("res://scripts/assessor_rig.gd"),
		"samples":_assessor_samples,"frames":_assessor_frames}, "\t") + "\n")
	file.close()
