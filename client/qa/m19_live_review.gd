extends "res://scripts/qa_tour.gd"

## Planned Works live review: a spectator watches the free local agent play
## the level and stills are taken at the moments that matter: the concourse,
## a jetpack burn, a strip being prepared and worked, the market at night,
## Latch on the tank and leaving, the roofs and the trench. Observations only;
## the agent's inputs are its own.
##
## Run against `fragr-server --bots 0 --map-file server/maps/m19-planned-works.json`
## with `fragr-agent-adapter scripted-bot` joined, on a real display:
## `FRAGR_SERVER=127.0.0.1:<port> FRAGR_QA_DIR=<out> godot --path client
## --script res://qa/m19_live_review.gd`. Stills land in FRAGR_QA_DIR.
const MANIFEST: String = "res://qa/m19-live-review.json"
const CHASE_BACK: float = 5.2
const CHASE_UP: float = 2.4

var _review_shots: Array[Dictionary] = []
var _review_taken: Dictionary = {}
var _review_busy: bool = false
var _review_last_ms: int = 0
var _review_chase: int = 0

## A tiling desktop resizes the window; stills keep the screen's own aspect
## and are scaled to 1280 wide, so the tour's fixed-size gate does not apply.
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
	if snapshot.is_empty() or mission.get("id") != MissionState.M19_ID:
		return false
	var agent: Dictionary = {}
	for actor: Dictionary in snapshot.get("players", []):
		if ActorState.is_participant(actor) and int(actor.get("hp", 0)) > 0:
			agent = actor
			break
	if agent.is_empty():
		return false
	var works: M19Works = game.get("m19_works")
	# Review only: show the agent's fuel gauge as the agent would see it.
	if works != null and works.active():
		works._gauge.present(WorksFacts.pack_for(snapshot, str(agent["id"])), true)
	var progress: Dictionary = mission.get("m19", {})
	var done: int = progress.get("completed", []).size()
	var feet: Vector3 = Vector3(float(agent["x"]), float(agent["y"]) - 1.5, float(agent["z"]))
	var yaw: float = float(agent.get("yaw", 0.0))
	var forward: Vector3 = Vector3(cos(yaw), 0.0, sin(yaw))
	var pack: Dictionary = WorksFacts.pack_for(snapshot, str(agent["id"]))
	var strips: Array = snapshot.get("paver_strips", [])
	if mission.get("phase") == "in_progress" and done == 0:
		root.mode = Window.MODE_FULLSCREEN
		_shot("concourse_entry", Vector3(-46.8, 2.8, -13.5), Vector3(-55.0, 0.9, -26.0))
	if pack.get("thrusting", false) and done <= 1:
		_shot("jetpack_burn", Vector3(-56.0, 2.2, -17.0), feet + Vector3(0.0, 1.0, 0.0))
	for strip: Dictionary in strips:
		var origin: Vector3 = Vector3(strip["origin"][0], strip["origin"][1], strip["origin"][2])
		var along: Vector3 = Vector3(cos(float(strip["yaw"])), 0.0, sin(float(strip["yaw"])))
		var side: Vector3 = Vector3(-along.z, 0.0, along.x)
		# Over the Paver's shoulder, down the strip it marked.
		var eye: Vector3 = origin - along * 3.2 + side * 1.4 + Vector3(0.0, 3.1, 0.0)
		var key: String = "strip_working" if strip["working"] else "strip_preparing"
		_shot(key, eye, origin + along * float(strip["length"]) * 0.5)
		_shot(key + "_shoulder", feet + Vector3(0.0, 2.3, 0.0) - forward * 2.2 + Vector3(-forward.z, 0.0, forward.x) * 0.6, origin + Vector3(0.0, 1.2, 0.0))
	if done == 4:
		_shot("market_night", Vector3(-4.0, 8.5, 10.0), Vector3(20.0, 0.5, 26.0))
		_shot("meal_table", Vector3(-13.5, 2.4, 20.0), Vector3(-19.0, 0.9, 25.0))
	if progress.get("current", {}).get("id", "") == "water_tanks" and works != null and works._latch_mode == "tank":
		_shot("latch_on_tank", Vector3(-38.0, 10.4, 17.0), M19Works.TANK_SEAT + Vector3(0.0, 0.6, 0.0))
		_shot("latch_seated", M19Works.TANK_SEAT + Vector3(3.2, 0.9, -2.4), M19Works.TANK_SEAT + Vector3(0.0, 0.3, 0.0))
	if works != null and works._latch_mode == "tank" and works._caption.visible:
		_shot("latch_lines", feet + Vector3(0.0, 2.2, 0.0) + (feet - Vector3(M19Works.TANK_SEAT.x, feet.y, M19Works.TANK_SEAT.z)).normalized() * 2.0, M19Works.TANK_SEAT + Vector3(0.0, 1.0, 0.0))
	if works != null and works._latch_mode == "running" and works._latch.visible:
		var latch: Vector3 = works._latch.global_position
		_shot("latch_leaves", latch + Vector3(5.0, 3.0, -5.0), latch + Vector3(0.0, 1.0, 0.0))
	if done == 6 and feet.y > 4.0:
		_shot("roofs_to_pier", feet + Vector3(0.0, 2.4, -1.5), Vector3(54.0, 3.0, 95.0))
	if done == 7:
		_shot("tram_trench", Vector3(53.0, 5.5, 20.0), Vector3(53.0, 0.5, 46.0))
	if progress.get("gate_open", false):
		_shot("waterworks_open", feet + Vector3(-5.0, 3.0, -4.0), Vector3(53.0, 1.5, 53.0))
	if mission.get("phase") == "departed":
		_shot("departed", Vector3(30.0, 9.0, 40.0), Vector3(55.0, 0.0, 80.0))
	# A chase frame every eight seconds for motion review.
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
	var filename: String = "m19_%02d_%s.png" % [_review_shots.size(), key]
	if frame != null and frame.save_png(_out_dir.path_join(filename)) == OK:
		var game: Node = _game_manager()
		_review_shots.append({"file": filename, "key": key, "tick": int(game.latest_snapshot.get("tick", -1)) if game != null else -1})
	_review_busy = false

func _write_manifest(tour: Dictionary) -> void:
	super._write_manifest(tour)
	var file: FileAccess = FileAccess.open(_out_dir.path_join("m19-review.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"schema": 1, "observations_only": true, "shots": _review_shots}, "\t") + "\n")
		file.close()
