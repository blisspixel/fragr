class_name M17Office
extends Node3D

## Peace Without Interruption Forever Office presenter. Voss's custody is
## the server's: her body and the two coalition people who take her are
## staged `figure` bodies in the snapshot, moved along authored walks from
## M17 `custody_started`. This presenter dresses them as people, gives Voss
## her three lines and puts the official caption on the chamber screen.
## Nothing here is collision, cover or an interaction target.
signal notice_requested(text: String)

const CAMERA = preload("res://scripts/spectator_cam.gd")

## Voss: institutional certainty, then colder and quieter, never louder.
const VOSS_LINES: Array[String] = ["M17_VOSS_SECURED_ROOM", "M17_VOSS_PROVIDED", "M17_VOSS_RUN_IT"]
## A client that first sees the custody this many ticks after it began (a
## late join or a resume) restages none of it.
const LATE_TICKS: int = 20
## The coalition: one free human and one free agent, each in their own
## colours (never Union black and red, never cyan, never off-white).
const COALITION: Array[Dictionary] = [
	{"person": "free_human", "tape": Color("c49a3e"), "coat": Color("5a6f4a"), "trousers": Color("4a4a3a"), "skin": Color("8a6d58")},
	{"person": "free_synthetic", "tape": Color("b0663a"), "coat": Color("4f6a8a"), "trousers": Color("3e4a5a"), "skin": Color("a89272")},
]

var _geometry: Dictionary = {}
var _core_seal_light: MeshInstance3D = null
var _bulkhead_lights: Array[MeshInstance3D] = []
var _kessel_secured: bool = false
var _core_unsealed: bool = false
var _voss_captured: bool = false
var _kessel_notice_fired: bool = false
var _core_notice_fired: bool = false
var _voss_notice_fired: bool = false
var state_applied: int = 0
## Spoken lines in play: sentence case with a speaker label.
var caption: SpeakerCaption
var _custody_started: int = -1
var _first_age: int = -1
var _spoken: bool = false
var _attempt: int = -1
## Figure id to its person and the server's latest feet and yaw.
var _figures: Dictionary[String, CivilianFigure] = {}
var _targets: Dictionary[String, Vector3] = {}
var _yaws: Dictionary[String, float] = {}
var _screen: WorldSign = null

func _init() -> void:
	caption = SpeakerCaption.new()
	caption.name = "OfficeCaptions"
	add_child(caption)

func clear_map() -> void:
	_geometry.clear()
	_core_seal_light = null
	_bulkhead_lights.clear()
	_kessel_secured = false
	_core_unsealed = false
	_voss_captured = false
	_kessel_notice_fired = false
	_core_notice_fired = false
	_voss_notice_fired = false
	state_applied = 0
	_reset_custody()
	_attempt = -1
	_figures.clear()
	_targets.clear()
	_yaws.clear()
	_screen = null
	for child: Node in get_children():
		if child == caption:
			continue
		remove_child(child)
		child.queue_free()

func _reset_custody() -> void:
	_custody_started = -1
	_first_age = -1
	_spoken = false
	if caption != null:
		caption.clear()

func active() -> bool:
	return not _geometry.is_empty()

func configure_map(info: Dictionary) -> void:
	clear_map()
	if not info.get("m17") is Dictionary or not MissionState.map_error(info).is_empty():
		return
	_geometry = MissionState.geometry_for(info)
	_build_office_visuals()
	# The command galleries' furniture, windows and lamps (presentation only).
	if M17Dressing.office_layout(info):
		var dressing: M17Dressing = M17Dressing.new()
		dressing.name = "OfficeDressing"
		add_child(dressing)
		dressing.configure_map(info)

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

func _build_office_visuals() -> void:
	# Core seal indicator bar over the security bulkhead at z=18.0
	_core_seal_light = _box("CoreSealLight", Vector3(0.0, 3.8, 18.0), Vector3(6.0, 0.3, 0.4), Color("c49a45"))
	# The gallery bulkhead over the exposed stair carries status lamps on its
	# jambs, both faces: amber while the Office holds it, green once the override opens
	# it onto the outer court stair. Paint and lamp only; the server owns the door.
	for jamb: float in [-19.82, -16.68]:
		_bulkhead_lights.append(_box("BulkheadLightGallery", Vector3(jamb, 4.0, 17.95), Vector3(0.12, 0.6, 0.1), Color("c49a45")))
		_bulkhead_lights.append(_box("BulkheadLightCourt", Vector3(jamb, 4.0, 20.05), Vector3(0.12, 0.6, 0.1), Color("c49a45")))
	# The chamber screen's official caption, still running behind the rostrum
	# while the Office falls. Diegetic: the screen's own words, not a notice.
	_screen = WorldSign.new()
	_screen.name = "ChamberScreenCaption"
	_screen.configure("WORLD_M17_SCREEN_CONTINUITY", Vector2(5.2, 0.7), WorldSign.PANEL_TEXT)
	_screen.position = Vector3(-4.0, 2.2, 33.96)
	_screen.rotation.y = PI
	_screen.layers = ArenaSky.WORLD_LAYERS
	add_child(_screen)

func apply_state(state: Dictionary) -> void:
	if state.get("id") != MissionState.M17_ID or not state.get("m17") is Dictionary:
		return
	state_applied += 1
	var progress: Dictionary = state["m17"]
	var kessel: bool = progress.get("kessel_secured") == true
	var unsealed: bool = progress.get("core_unsealed") == true
	var voss: bool = progress.get("voss_captured") == true
	# A retry starts the morning over: nobody has come for her.
	var attempt: int = int(state.get("attempt", 0))
	if _attempt >= 0 and attempt != _attempt:
		_reset_custody()
		_voss_notice_fired = false
	_attempt = attempt
	var started: Variant = progress.get("custody_started")
	if started == null and _custody_started >= 0:
		_reset_custody()
	_custody_started = int(started) if started is float or started is int else -1

	if kessel and not _kessel_notice_fired:
		_kessel_notice_fired = true
		_kessel_secured = true
		notice_requested.emit(tr("M17_KESSEL_SECURED"))

	if unsealed and not _core_notice_fired:
		_core_notice_fired = true
		_core_unsealed = true
		if _core_seal_light != null and _core_seal_light.material_override is StandardMaterial3D:
			(_core_seal_light.material_override as StandardMaterial3D).albedo_color = Color("2ed158")
		for lamp: MeshInstance3D in _bulkhead_lights:
			if lamp.material_override is StandardMaterial3D:
				(lamp.material_override as StandardMaterial3D).albedo_color = Color("2ed158")
		notice_requested.emit(tr("M17_CORE_UNSEALED"))

	# No banner for Voss: the coalition walking her out is the capture.
	if voss and not _voss_notice_fired:
		_voss_notice_fired = true
		_voss_captured = true

## Figures and Voss's lines run on the snapshot clock, with the bodies.
func apply_snapshot(snapshot: Dictionary) -> void:
	if not active() or not snapshot.get("players") is Array:
		return
	var present: Dictionary[String, bool] = {}
	for actor: Variant in snapshot["players"]:
		if not actor is Dictionary or not ActorState.is_figure(actor):
			continue
		var id: String = str(actor["id"])
		present[id] = true
		_targets[id] = Vector3(float(actor["x"]), float(actor["y"]) - CAMERA.FP_SERVER_REFERENCE_Y, float(actor["z"]))
		_yaws[id] = float(actor.get("yaw", 0.0))
		if not _figures.has(id):
			_figures[id] = _person(ActorState.figure_kind(actor), _figures.size())
			_figures[id].place_feet(_targets[id])
	for id: String in _figures.keys():
		if not present.has(id):
			_figures[id].queue_free()
			_figures.erase(id)
			_targets.erase(id)
			_yaws.erase(id)
	if _custody_started >= 0 and snapshot.get("tick") is float:
		present_custody(int(snapshot["tick"]) - _custody_started)

## Voss says her three lines from the custody's first tick. Seen first from
## well into it, nothing is restaged.
func present_custody(age: int) -> void:
	if age < 0:
		return
	if _first_age < 0:
		_first_age = age
	if _first_age >= LATE_TICKS or _spoken:
		return
	_spoken = true
	var lines: Array[String] = []
	for key: String in VOSS_LINES:
		lines.append(tr(key))
	caption.say(lines)

func _person(kind: String, index: int) -> CivilianFigure:
	var figure: CivilianFigure = CivilianFigure.new()
	if kind == "voss":
		figure.name = "Voss"
		figure.configure("free_human", FactionPalette.UNION_RED)
		if figure.skin != null:
			# The Union's own: the issued black coat and its red band.
			figure.skin.dress("union", FactionPalette.UNION_RED)
	else:
		var look: Dictionary = COALITION[index % COALITION.size()]
		figure.name = "Coalition%d" % index
		figure.configure(str(look["person"]), look["tape"])
		if figure.skin != null:
			CrowdLook.outfit(figure.skin, look["coat"], look["trousers"], look["skin"])
			if look["person"] == "free_synthetic":
				CrowdLook.face_lamp(figure.skin, Color("ffb860"))
	add_child(figure)
	return figure

func _process(delta: float) -> void:
	for id: String in _figures:
		var figure: CivilianFigure = _figures[id]
		var target: Vector3 = _targets[id]
		var next: Vector3 = figure.position.lerp(target, clampf(delta * 12.0, 0.0, 1.0))
		figure.place_feet(next)
		if next.distance_to(target) < 0.02:
			# Standing: face where the server faces (atan2(dz, dx)); a figure's
			# mesh faces local +Z.
			var yaw: float = _yaws[id]
			figure.rotation.y = atan2(cos(yaw), sin(yaw))

func figure_count() -> int:
	return _figures.size()
