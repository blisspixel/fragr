extends "res://scripts/qa_tour.gd"

## All Systems Normal live review: a spectator watches the free local agent
## make the delivery and stills are taken at the turn's moments: the square
## at work, the heads coming round, Latch looking at the party, the square
## moving again, then the route. Observations only; the agent's inputs are
## its own.
##
## Run against `fragr-server --bots 0 --map-file server/maps/m18-all-systems-normal.json`
## with `fragr-agent-adapter scripted-bot` joined, on a real display:
## `FRAGR_SERVER=127.0.0.1:<port> FRAGR_QA_DIR=<out> godot --path client
## --script res://qa/m18_live_review.gd`. Stills land in FRAGR_QA_DIR.
const MANIFEST: String = "res://qa/m18-live-review.json"
const CHASE_BACK: float = 5.2
const CHASE_UP: float = 2.4
## Over the square from its west side, the depot and the work in view.
const SQUARE_EYE: Vector3 = Vector3(-40.0, 2.0, 10.0)
const SQUARE_FOCUS: Vector3 = Vector3(-26.0, 1.0, -4.0)

var _review_shots: Array[Dictionary] = []
var _review_taken: Dictionary = {}
var _review_busy: bool = false
var _review_last_ms: int = 0
var _review_chase: int = 0

func _ensure_capture_window_size(_label: String) -> bool:
	return true

func _load_manifest() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(MANIFEST)) as Dictionary

func _process(delta: float) -> bool:
	super._process(delta)
	var game: Node = _game_manager()
	if game == null or _review_busy or _out_dir.is_empty():
		return false
	var snapshot: Dictionary = game.latest_snapshot
	var mission: Dictionary = game.net_client.mission.get("state", {}) if game.net_client != null else {}
	if snapshot.is_empty() or mission.get("id") != MissionState.M18_ID:
		return false
	root.mode = Window.MODE_FULLSCREEN
	var agent: Dictionary = {}
	var latch: Dictionary = {}
	for actor: Dictionary in snapshot.get("players", []):
		if ActorState.is_participant(actor) and int(actor.get("hp", 0)) > 0 and agent.is_empty():
			agent = actor
		var campaign: Variant = actor.get("campaign")
		if campaign is Dictionary and campaign.get("side") == "companion":
			latch = actor
	if agent.is_empty():
		return false
	var progress: Dictionary = mission.get("m18", {})
	var done: int = progress.get("completed", []).size()
	var tick: int = int(snapshot.get("tick", 0))
	var feet: Vector3 = Vector3(float(agent["x"]), float(agent["y"]) - 1.5, float(agent["z"]))
	var yaw: float = float(agent.get("yaw", 0.0))
	var forward: Vector3 = Vector3(cos(yaw), 0.0, sin(yaw))
	var started: Variant = progress.get("turn_started")
	if mission.get("phase") == "in_progress" and started == null:
		_shot("square_morning", SQUARE_EYE, SQUARE_FOCUS)
		if not latch.is_empty():
			var l: Vector3 = Vector3(float(latch["x"]), float(latch["y"]) - 1.5, float(latch["z"]))
			_shot("latch_with_crate", l + Vector3(-3.0, 1.9, -2.6), l + Vector3(0.0, 1.2, 0.0))
	if started is float:
		var age: int = tick - int(started)
		if age >= 2 and age < M18Transit.HEADS_TURN_TICKS:
			_shot("turn_stopped", SQUARE_EYE, SQUARE_FOCUS)
		if age >= M18Transit.HEADS_TURN_TICKS + 4 and age < M18Transit.LATCH_LOOKS_TICKS:
			_shot("turn_heads", SQUARE_EYE, SQUARE_FOCUS)
		if age >= M18Transit.HEADS_TURN_TICKS + 8 and age < M18Transit.TURN_TICKS:
			_shot("turn_supervisor", Vector3(-42.0, 2.0, 4.0), Vector3(-27.0, 1.2, -4.0))
		if age >= M18Transit.LATCH_LOOKS_TICKS + 8 and age < M18Transit.TURN_TICKS and not latch.is_empty():
			# From behind the agent's shoulder, toward Latch looking back.
			# From the party's side, a little off Latch's line of sight, onto
			# Latch's face; the square's turned machines beyond.
			var l: Vector3 = Vector3(float(latch["x"]), float(latch["y"]) - 1.5, float(latch["z"]))
			var to_agent: Vector3 = Vector3(feet.x - l.x, 0.0, feet.z - l.z)
			to_agent = to_agent.normalized() if to_agent.length() > 0.1 else Vector3(-1.0, 0.0, 0.0)
			_shot("turn_latch_looks", l + to_agent * 2.6 + Vector3(-to_agent.z, 0.0, to_agent.x) * 0.9 + Vector3(0.0, 1.6, 0.0), l + Vector3(0.0, 1.45, 0.0))
		if age >= M18Transit.TURN_TICKS + 6 and age < M18Transit.TURN_TICKS + 40:
			_shot("turn_moves", SQUARE_EYE, SQUARE_FOCUS)
		if age >= M18Transit.TURN_TICKS + 20 and age < M18Transit.TURN_TICKS + 80:
			_shot("turn_after_lines", feet - forward * CHASE_BACK + Vector3(0.0, CHASE_UP, 0.0), feet + forward * 3.0 + Vector3(0.0, 1.0, 0.0))
	if done == 5:
		_shot("overlook", feet + Vector3(0.0, 2.0, 0.0) - forward * 2.0, feet + forward * 20.0)
	if Time.get_ticks_msec() - _review_last_ms > 8000:
		_review_chase += 1
		_shot("chase_%02d" % _review_chase, feet - forward * CHASE_BACK + Vector3(0.0, CHASE_UP, 0.0), feet + forward * 3.0 + Vector3(0.0, 1.0, 0.0))
	return false

func _shot(key: String, eye: Vector3, focus: Vector3) -> void:
	if _review_taken.has(key) or _review_busy:
		return
	_review_taken[key] = true
	_review_busy = true
	_review_last_ms = Time.get_ticks_msec()
	_take.call_deferred(key, eye, focus)

func _take(key: String, eye: Vector3, focus: Vector3) -> void:
	var cam: Node3D = _spectator_camera() as Node3D
	if cam != null:
		cam.set("spectator_first_person", false)
		cam.set("follow_mode", false)
		cam.set("fp_mode", false)
		cam.global_position = eye
		cam.look_at(focus, Vector3.UP)
		cam.set("tip_locked_transform", cam.global_transform)
		cam.set("tip_has_locked_transform", true)
		cam.set("tip_pose_lock", true)
	for _frame: int in range(3):
		await RenderingServer.frame_post_draw
	var frame: Image = _grab()
	if frame != null and frame.get_width() > 1280:
		frame.resize(1280, roundi(float(frame.get_height()) * 1280.0 / float(frame.get_width())), Image.INTERPOLATE_BILINEAR)
	var filename: String = "m18_%02d_%s.png" % [_review_shots.size(), key]
	if frame != null and frame.save_png(_out_dir.path_join(filename)) == OK:
		var game: Node = _game_manager()
		_review_shots.append({"file": filename, "key": key, "tick": int(game.latest_snapshot.get("tick", -1)) if game != null else -1})
	_review_busy = false

func _write_manifest(tour: Dictionary) -> void:
	super._write_manifest(tour)
	var file: FileAccess = FileAccess.open(_out_dir.path_join("m18-review.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"schema": 1, "observations_only": true, "shots": _review_shots}, "\t") + "\n")
		file.close()
