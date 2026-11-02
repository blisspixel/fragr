extends "res://qa/m18_live_review.gd"

## Peace Without Interruption custody review: a spectator watches the free
## local agent clear the Office and secure Voss, and stills are taken from
## fixed cameras on her custody's server clock: Voss beside her rostrum
## before it, then a strip every second from the Use while the coalition
## comes in, she speaks and they walk her out, then the three under guard.
## Observations only; the agent's inputs are its own.
##
## Run against `localexception-server --bots 0 --map-file server/maps/m17-peace-without-interruption.json`
## with `localexception-agent-adapter scripted-bot` joined, on a real display, via
## tools/qa_tour.sh with LOCALEXCEPTION_QA_SCRIPT=res://qa/m17_live_review.gd and
## LOCALEXCEPTION_QA_MANIFEST=res://qa/m17-live-review.json. Stills land in LOCALEXCEPTION_QA_DIR.
const M17_MANIFEST: String = "res://qa/m17-live-review.json"
## Inside the chamber by the core seal: Voss beside the rostrum's east end
## with the seal behind her, the party at the rostrum off to one side and
## the east door they come in by, in one frame.
const CHAMBER_EYE: Vector3 = Vector3(2.0, 2.4, 21.0)
const CHAMBER_FOCUS: Vector3 = Vector3(8.0, 1.1, 29.5)
## Outside the east door and a little above: the walk out and the three
## waiting, seen across their line so nobody stands behind anybody.
const DOOR_EYE: Vector3 = Vector3(17.0, 3.2, 31.5)
const DOOR_FOCUS: Vector3 = Vector3(20.0, 1.0, 22.5)
const STRIP_EVERY: int = 20

func _load_manifest() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(M17_MANIFEST)) as Dictionary

func _process(delta: float) -> bool:
	_m17_review()
	return super._process(delta)

func _m17_review() -> void:
	var game: Node = _game_manager()
	if game == null or _review_busy or _out_dir.is_empty():
		return
	var snapshot: Dictionary = game.latest_snapshot
	var mission: Dictionary = game.net_client.mission.get("state", {}) if game.net_client != null else {}
	if snapshot.is_empty() or mission.get("id") != MissionState.M17_ID:
		return
	root.mode = Window.MODE_FULLSCREEN
	var progress: Dictionary = mission.get("m17", {})
	var done: int = progress.get("completed", []).size()
	var tick: int = int(snapshot.get("tick", 0))
	var started: Variant = progress.get("custody_started")
	if done >= 4 and started == null:
		_shot("m17_voss_waits", CHAMBER_EYE, CHAMBER_FOCUS)
	if started is float:
		var age: int = tick - int(started)
		var step: int = age / STRIP_EVERY
		if step <= 13:
			_shot("m17_custody_%02d" % step, CHAMBER_EYE, CHAMBER_FOCUS)
		elif step <= 24:
			_shot("m17_custody_%02d" % step, DOOR_EYE, DOOR_FOCUS)
		elif step >= 30:
			_shot("m17_under_guard", DOOR_EYE, DOOR_FOCUS)
