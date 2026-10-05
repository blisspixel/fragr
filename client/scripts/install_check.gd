class_name InstallCheck
extends Node
## `fragr --headless -- --check-install` asks the bundled fragr-server for a run
## preview, then verifies owned arena readiness, real snapshots and shutdown.
## In an exported build the server must sit beside the game executable.

signal finished(passed: bool)

const FLAG: String = "--check-install"
const TIMEOUT_MS: int = 15000

var quit_when_done: bool = true
var _local: LocalMatch
var _deadline: int = 0
var _phase: String = "preview"
var _host: LocalHost
var _owns_host: bool = false
var _host_pid: int = -1
var _preset: int = 0
var _peer: Node
var _map: Dictionary = {}
var _snapshot: Dictionary = {}
var _preview_status: String = ""

static func requested() -> bool:
	return FLAG in OS.get_cmdline_user_args()

func _init(local: LocalMatch) -> void:
	_local = local

func _ready() -> void:
	var workbench: Node3D = ShipFurnishings.instantiate_source()
	var workbench_problem: String = ShipFurnishings.source_error(workbench)
	if workbench != null:
		workbench.free()
	if not workbench_problem.is_empty():
		_finish(false, "the packaged ship workbench is missing or invalid")
		return
	# Live cast resources belong in the export, unlike offline source-art tools.
	if not ResourceLoader.exists(LatchSource.LATCH_SOURCE, "PackedScene"):
		_finish(false, "the live Latch mesh is missing from this build")
		return
	var latch: LatchView = LatchView.new()
	var skin: Skeleton3D = latch._source_body.get_node_or_null("Armature/Skeleton3D") as Skeleton3D
	var mesh: MeshInstance3D = latch._source_body.get_node_or_null("Armature/Skeleton3D/char1") as MeshInstance3D
	var player: AnimationPlayer = latch._source_body.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var live_available: bool = skin != null and skin.find_bone("RightHand") >= 0 \
		and mesh != null and mesh.skin != null and player != null and player.has_animation(&"walk")
	latch.free()
	if not live_available:
		_finish(false, "the live Latch skin or walking clip is missing from this build")
		return
	# The Enforcer uses packaged directional surfaces, never offline source art.
	for path: String in ["res://assets/characters/union/enforcer.png",
		"res://assets/characters/union/enforcer_normals.png"]:
		if not ResourceLoader.exists(path, "Texture2D") or not load(path) is Texture2D:
			_finish(false, "the Enforcer surfaces are missing from this build")
			return
	# Scene manifests are plain JSON; the export filter must carry them.
	if not StoryScene.exists(CampaignOpening.SCENE_ID):
		_finish(false, "the story scene manifests are missing from this build")
		return
	for id: String in ["m05_arrival", "l05_l06"]:
		var scene: Dictionary = StoryScene.load_scene(id)
		if scene.is_empty():
			_finish(false, "the M05 story manifests are missing or invalid")
			return
		for shot: Dictionary in scene["shots"]:
			if TranslationServer.translate(shot["caption_key"]) == shot["caption_key"] or StoryScene.narration_path(shot, "en").is_empty():
				_finish(false, "the M05 story copy or narration is missing")
				return
	for path: String in ["res://assets/story/effects/grenade_bounce.wav", "res://assets/story/effects/grenade_blast.wav"]:
		if not ResourceLoader.exists(path) or not load(path) is AudioStream:
			_finish(false, "the grenade effects are missing from this build")
			return
	for id: String in ["m06_arrival", "l06_l07"]:
		var scene: Dictionary = StoryScene.load_scene(id)
		if scene.is_empty():
			_finish(false, "the M06 story manifests are missing or invalid")
			return
		for key: String in StoryScene.catalog_keys(scene):
			if TranslationServer.translate(key) == key:
				_finish(false, "the M06 localized story copy is missing")
				return
		for shot: Dictionary in scene["shots"]:
			if StoryScene.narration_path(shot, "en").is_empty():
				_finish(false, "the lunar narration is missing")
				return
			if not ResourceLoader.exists(str(shot.get("image", "")), "Texture2D"):
				_finish(false, "the M06 story illustrations are missing")
				return
	# Level 7's pages reuse existing keyed text and stills; they carry no narration.
	for id: String in ["m07_arrival", "l07_l08"]:
		var scene: Dictionary = StoryScene.load_scene(id)
		if scene.is_empty():
			_finish(false, "the M07 story manifests are missing or invalid")
			return
		for key: String in StoryScene.catalog_keys(scene):
			if TranslationServer.translate(key) == key:
				_finish(false, "the M07 localized story copy is missing")
				return
		for shot: Dictionary in scene["shots"]:
			if not ResourceLoader.exists(str(shot.get("image", "")), "Texture2D"):
				_finish(false, "the M07 story illustrations are missing")
				return
	# M10 deliberately retains keyed reader-paced text until its own voice/art gate.
	for id: String in ["m10_arrival", "l10_l11"]:
		var scene: Dictionary = StoryScene.load_scene(id)
		if scene.is_empty():
			_finish(false, "the ship story manifests are missing or invalid")
			return
		for key: String in StoryScene.catalog_keys(scene):
			if TranslationServer.translate(key) == key:
				_finish(false, "the ship story copy is missing")
				return
	var lunar_bed: AudioStreamWAV = load("res://assets/story/ambience/lunar_port_utility.wav") as AudioStreamWAV
	if lunar_bed == null or lunar_bed.loop_mode != AudioStreamWAV.LOOP_FORWARD:
		_finish(false, "the lunar utility loop is missing or not looping")
		return
	for name: String in ["dust", "pressure_shell", "earth", "drawing"]:
		if not ResourceLoader.exists("res://assets/environment/moon/" + name + ".png"):
			_finish(false, "the lunar pixel surfaces are missing")
			return
	var path: String = _local.executable_path()
	if path.is_empty():
		_finish(false, "no fragr-server beside %s" % OS.get_executable_path())
		return
	if not OS.has_feature("editor") and path.get_base_dir() != OS.get_executable_path().get_base_dir():
		_finish(false, "an exported build resolved %s outside its own directory" % path)
		return
	_local.run_preview_changed.connect(_on_preview)
	_deadline = Time.get_ticks_msec() + TIMEOUT_MS
	_local.refresh_run_preview()

func _process(_delta: float) -> void:
	if _deadline > 0 and Time.get_ticks_msec() > _deadline:
		_finish(false, _phase + " timed out")
		return
	if _deadline <= 0 or _phase == "preview":
		return
	if _host.state == LocalHost.State.FAILED:
		_finish(false, "the arena child failed during " + _phase)
		return
	if _phase == "starting" and _host.state == LocalHost.State.RUNNING:
		_connect_arena()
	elif _phase == "wire" and not _map.is_empty() and not _snapshot.is_empty():
		var map_id: int = 1 if _preset == 0 else 4
		var mode: String = "tdm" if _preset == 0 else "sabotage"
		var rules: Dictionary = MatchRules.parse(_map.get("rules"))
		if _map.get("map_id") != map_id or _snapshot.get("map_id") != map_id or rules.get("mode") != mode:
			_finish(false, "the arena wire did not match its ready preset")
			return
		_close_peer()
		_host.stop()
		_phase = "stopping"
		_deadline = Time.get_ticks_msec() + TIMEOUT_MS
	elif _phase == "stopping" and _host.state == LocalHost.State.IDLE:
		if OS.is_process_running(_host_pid):
			_finish(false, "the owned arena process survived Stop")
			return
		print("fragr install check: arena ", "tdm" if _preset == 0 else "5v5 sabotage", " ready, wire and owned Stop PASS")
		_owns_host = false
		_host_pid = -1
		if _preset == 0:
			_preset = 1
			_start_arena()
		else:
			_finish(true, "server %s answered %s; TDM and 5v5 Sabotage ready, wire and owned Stop passed" % [_local.executable_path(), _preview_status])

func _on_preview() -> void:
	var status: String = str(_local.run_preview.get("status", ""))
	if status == "loading":
		return
	if status.is_empty() or status == "unavailable":
		_finish(false, "the server did not answer a run preview")
		return
	_preview_status = status
	_local.run_preview_changed.disconnect(_on_preview)
	_host = LocalHost.for_tree(get_tree())
	_start_arena()

func _start_arena() -> void:
	if _host.executable_path() != _local.executable_path():
		_finish(false, "the arena and campaign resolved different bundled servers")
		return
	_map.clear()
	_snapshot.clear()
	_phase = "starting"
	_deadline = Time.get_ticks_msec() + TIMEOUT_MS
	var options: Dictionary = {"mode": "tdm" if _preset == 0 else "sabotage",
		"map_id": 1 if _preset == 0 else 4, "bots": 0, "bot_policy": "none", "fill_target": 0, "lan": false, "port": 0}
	if not _host.start_host(options):
		_finish(false, "the bundled server could not start its arena preset")
		return
	_owns_host = true
	_host_pid = _host.process._pid

func _connect_arena() -> void:
	_peer = load("res://scripts/net_client.gd").new()
	add_child(_peer)
	_peer.map_info_received.connect(func(info: Dictionary) -> void: _map = info.duplicate(true))
	_peer.snapshot_received.connect(func(info: Dictionary) -> void: _snapshot = info.duplicate(true))
	_peer.server_error.connect(func(_message: String) -> void: _finish(false, "the arena wire was refused or invalid"))
	_peer.set_server_host(_host.url)
	_phase = "wire"
	_deadline = Time.get_ticks_msec() + TIMEOUT_MS
	if not _peer.connect_to_server("spectator", "InstallCheck"):
		_finish(false, "the arena socket did not connect")

func _close_peer() -> void:
	if is_instance_valid(_peer):
		_peer.leave_match()
		_peer.queue_free()
	_peer = null

func _exit_tree() -> void:
	_close_peer()
	if _owns_host and is_instance_valid(_host):
		_host.stop()
		_host.process.dispose()
	_owns_host = false

func _finish(passed: bool, detail: String) -> void:
	if _deadline < 0:
		return
	_deadline = -1
	_close_peer()
	if _owns_host and is_instance_valid(_host):
		_host.stop()
		_host.process.dispose()
		if _host_pid > 0 and OS.is_process_running(_host_pid):
			passed = false
			detail = "the failed check could not retire its owned arena process"
	_owns_host = false
	if _local.run_preview_changed.is_connected(_on_preview):
		_local.run_preview_changed.disconnect(_on_preview)
	if passed:
		print("fragr install check: PASS, ", detail)
	else:
		printerr("fragr install check: FAIL, " + detail)
	finished.emit(passed)
	if quit_when_done:
		get_tree().quit(0 if passed else 1)
