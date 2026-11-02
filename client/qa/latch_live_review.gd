extends "res://scripts/qa_tour.gd"

## Latch in Levels 12, 13, 14 and 16: a spectator watches the free local
## agent play and stills are taken of Latch with the party, at each line
## Latch says and on a chase behind the agent with Latch in frame.
## Observations only; the agent's inputs are its own.
##
## Run against `localexception-server --bots 0 --map-file server/maps/<level>.json`
## with `localexception-agent-adapter scripted-bot` joined:
## `LOCALEXCEPTION_QA_MANIFEST=res://qa/latch-live-review.json
## LOCALEXCEPTION_QA_SCRIPT=res://qa/latch_live_review.gd tools/qa_tour.sh <out>`.
const MANIFEST: String = "res://qa/latch-live-review.json"
const CHASE_BACK: float = 4.6
const CHASE_UP: float = 2.2

var _review_shots: Array[Dictionary] = []
var _review_taken: Dictionary = {}
var _review_busy: bool = false
var _review_last_ms: int = 0
var _review_chase: int = 0
var _review_line: String = ""

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
	if snapshot.is_empty() or mission.is_empty():
		return false
	root.mode = Window.MODE_FULLSCREEN
	var agent: Dictionary = {}
	var latch: Dictionary = {}
	for actor: Dictionary in snapshot.get("players", []):
		if ActorState.is_participant(actor) and int(actor.get("hp", 0)) > 0 and agent.is_empty():
			agent = actor
		if ActorState.is_companion(actor):
			latch = actor
	if agent.is_empty():
		return false
	var level: String = str(mission.get("id", "level"))
	var feet: Vector3 = Vector3(float(agent["x"]), float(agent["y"]) - 1.5, float(agent["z"]))
	var yaw: float = float(agent.get("yaw", 0.0))
	var forward: Vector3 = Vector3(cos(yaw), 0.0, sin(yaw))
	if not latch.is_empty():
		var l: Vector3 = Vector3(float(latch["x"]), float(latch["y"]) - 1.5, float(latch["z"]))
		# From behind the agent's shoulder toward Latch, raised, so both read.
		var across: Vector3 = Vector3(l.x - feet.x, 0.0, l.z - feet.z)
		var gap: float = across.length()
		across = across.normalized() if gap > 0.1 else Vector3(1.0, 0.0, 0.0)
		var side: Vector3 = Vector3(-across.z, 0.0, across.x)
		var behind: Vector3 = feet - across * 2.6 + side * 1.2 + Vector3(0.0, 2.2, 0.0)
		if gap < 9.0:
			_shot(level + "_latch_with_party", behind, l + Vector3(0.0, 1.1, 0.0))
		var lines: Node = game.get("latch_lines")
		var said: String = str(lines.call("showing")) if lines != null else ""
		if not said.is_empty() and said != _review_line and not _review_busy:
			_review_line = said
			_shot(level + "_line_%d" % _review_shots.size(), behind, l + Vector3(0.0, 1.2, 0.0))
		# A moment later, Latch on the way to the party.
		if gap < 6.0 and _review_taken.has(level + "_latch_with_party"):
			_shot(level + "_latch_close", feet + across * gap * 0.5 + side * 2.6 + Vector3(0.0, 1.7, 0.0), (feet + l) * 0.5 + Vector3(0.0, 1.1, 0.0))
	if Time.get_ticks_msec() - _review_last_ms > 12000:
		_review_chase += 1
		_shot("%s_chase_%02d" % [level, _review_chase], feet - forward * CHASE_BACK + Vector3(0.0, CHASE_UP, 0.0), feet + forward * 3.0 + Vector3(0.0, 1.0, 0.0))
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
	var filename: String = "latch_%02d_%s.png" % [_review_shots.size(), key]
	if frame != null and frame.save_png(_out_dir.path_join(filename)) == OK:
		var game: Node = _game_manager()
		_review_shots.append({"file": filename, "key": key, "tick": int(game.latest_snapshot.get("tick", -1)) if game != null else -1})
	_review_busy = false

func _write_manifest(tour: Dictionary) -> void:
	super._write_manifest(tour)
	var file: FileAccess = FileAccess.open(_out_dir.path_join("latch-review.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"schema": 1, "observations_only": true, "shots": _review_shots}, "\t") + "\n")
		file.close()
