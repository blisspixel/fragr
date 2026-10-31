class_name M18Transit
extends Node3D

## All Systems Normal presenter: the recovery square's ordinary morning, the
## turn, and the transit concourse. The server decides the turn
## (`m18.turn_started`) and does it: the machines stop, their heads come round
## together, their control passes, Latch looks at the party. This presenter
## only gives it its silence, its rhythm and its few spoken lines. Nothing
## here is collision, cover or an interaction target.
signal notice_requested(text: String)
## A campaign score cue for this moment (CampaignScore slot id).
signal story_cue(slot: String)
## The air goes out of the world at the turn, and comes back after it.
signal hush(on: bool)
## Latch's face for the rest of the level ("" lets it go): concerned once
## Latch has looked at the party.
signal latch_expression(expression: String)

## Mirrors of the server's turn timing (`protocol/m18.rs`), in ticks.
const TURN_TICKS: int = 60
const HEADS_TURN_TICKS: int = 10
const LATCH_LOOKS_TICKS: int = 24
## The supervisor notices a beat after the heads come round.
const SUPERVISOR_TICKS: int = 16
const TURN_CUE: String = "cue-l18"
const ARRIVAL_LINES: Array[String] = ["M18_LATCH_CURSED", "M18_LATCH_CONTRACT"]
const SUPERVISOR_LINES: Array[String] = ["M18_SUPERVISOR_RESPOND"]
const AFTER_LINES: Array[String] = ["M18_LATCH_ALL_AT_ONCE", "M18_LATCH_STILL_HERE"]

var _geometry: Dictionary = {}
var _gate_light: MeshInstance3D = null
var _roadblock_marker: MeshInstance3D = null
var _notices: Dictionary[String, bool] = {}
var _beats: Dictionary[String, bool] = {}
var _attempt: int = -1
var _turn_started: int = -1
var _hushed: bool = false
## Spoken lines in play: sentence case with a speaker label.
var caption: SpeakerCaption
var state_applied: int = 0
## Ticks into the turn when this client first saw it; a late join or a resume
## past the turn presents nothing of it.
var _first_age: int = -1

func _init() -> void:
	caption = SpeakerCaption.new()
	caption.name = "TransitCaptions"
	add_child(caption)

func clear_map() -> void:
	_geometry.clear()
	_gate_light = null
	_roadblock_marker = null
	_reset_story()
	_attempt = -1
	state_applied = 0
	for child: Node in get_children():
		if child == caption:
			continue
		remove_child(child)
		child.queue_free()

func _reset_story() -> void:
	_notices.clear()
	_turn_started = -1
	_first_age = -1
	if caption != null:
		caption.clear()
	if _beats.has("latch_looks"):
		latch_expression.emit("")
	_beats.clear()
	_release()

func _release() -> void:
	EnemyView.signal_window = Vector2i(-1, -1)
	if _hushed:
		_hushed = false
		hush.emit(false)

func active() -> bool:
	return not _geometry.is_empty()

func configure_map(info: Dictionary) -> void:
	clear_map()
	if not info.get("m18") is Dictionary or not MissionState.map_error(info).is_empty():
		return
	_geometry = MissionState.geometry_for(info)
	_build_transit_visuals()

func _box(label: String, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	node.layers = ArenaSky.WORLD_LAYERS
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	node.material_override = material
	add_child(node)
	return node

func _build_transit_visuals() -> void:
	# Warning barricade light at clinic roadblock
	_roadblock_marker = _box("RoadblockMarker", Vector3(-4.0, 4.6, 0.0), Vector3(10.0, 0.3, 0.4), Color("e0633b"))
	# Concourse departure gate clearance light at x=61.0, y=8.8, z=0.0
	_gate_light = _box("ConcourseGateLight", Vector3(61.0, 8.8, 0.0), Vector3(2.0, 0.3, 0.4), Color("c49a45"))

func _once(key: String, action: Callable) -> void:
	if _notices.has(key):
		return
	_notices[key] = true
	action.call()

func _beat(key: String, action: Callable) -> void:
	if _beats.has(key):
		return
	_beats[key] = true
	action.call()

func _say(keys: Array[String]) -> void:
	var lines: Array[String] = []
	for key: String in keys:
		lines.append(tr(key))
	caption.say(lines)

func apply_state(state: Dictionary) -> void:
	if not active() or state.get("id") != MissionState.M18_ID or not state.get("m18") is Dictionary:
		return
	state_applied += 1
	var progress: Dictionary = state["m18"]
	var completed: Array = progress.get("completed", [])
	var attempt: int = int(state.get("attempt", 0))
	# A retry starts the morning over: the square works again, nothing turned.
	if _attempt >= 0 and attempt != _attempt:
		_reset_story()
	_attempt = attempt
	var started: Variant = progress.get("turn_started")
	if started == null and _turn_started >= 0:
		_reset_story()
	_turn_started = int(started) if started is float or started is int else -1
	if str(state.get("phase", "")) == "in_progress" and completed.is_empty() and _turn_started < 0:
		_beat("arrival", func() -> void: _say(ARRIVAL_LINES))
	var challenges: Dictionary = progress.get("challenges", {})
	if challenges.get("aid_delivered") == true:
		_once("aid", func() -> void: notice_requested.emit(tr("M18_AID_DELIVERED")))
	if challenges.get("square_defended") == true:
		_once("square", func() -> void: notice_requested.emit(tr("M18_SQUARE_DEFENDED")))
	if challenges.get("collector_neutralized") == true:
		_once("roadblock", func() -> void: notice_requested.emit(tr("M18_COLLECTOR_NEUTRALIZED")))
	if progress.get("overlook_witnessed") == true:
		_once("overlook", func() -> void: notice_requested.emit(tr("M18_OVERLOOK_WITNESSED")))
	if progress.get("concourse_secured") == true:
		_once("concourse", func() -> void:
			if _gate_light != null and _gate_light.material_override is StandardMaterial3D:
				(_gate_light.material_override as StandardMaterial3D).albedo_color = Color("2ed158")
			notice_requested.emit(tr("M18_CONCOURSE_SECURED")))

## The turn runs on the snapshot clock, so it lands with the bodies.
func apply_snapshot(snapshot: Dictionary) -> void:
	if not active() or _turn_started < 0 or not snapshot.get("tick") is float:
		return
	present_turn(int(snapshot["tick"]) - _turn_started)

## One step of the turn's presentation at `age` ticks into it.
func present_turn(age: int) -> void:
	if age < 0:
		return
	if _first_age < 0:
		_first_age = age
	# Seen from the middle of a run that already turned: nothing to restage.
	if _first_age >= TURN_TICKS:
		return
	if age < TURN_TICKS:
		_beat("hush", func() -> void:
			caption.clear()
			_hushed = true
			hush.emit(true))
		EnemyView.signal_window = Vector2i(_turn_started + HEADS_TURN_TICKS, _turn_started + TURN_TICKS)
	if age >= LATCH_LOOKS_TICKS:
		_beat("latch_looks", func() -> void: latch_expression.emit("concerned"))
	if age >= SUPERVISOR_TICKS and age < TURN_TICKS:
		_beat("supervisor", func() -> void: _say(SUPERVISOR_LINES))
	if age >= TURN_TICKS:
		_beat("after", func() -> void:
			_release()
			story_cue.emit(TURN_CUE)
			caption.clear()
			_say(AFTER_LINES))

func hushed() -> bool:
	return _hushed
