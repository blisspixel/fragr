class_name M09Berth
extends Node3D

## The ship's details add no collision. Current people and feet come only
## from accepted mission facts; named Tern and Edda share their M10 live skins.
## The hull's name, the impound notice on the hatch and every state-driven
## fitting live here; the static berth is M09Dressing, which survives the
## MapInfo re-sent when the hatch opens.
const TINTS: Dictionary[String, Color] = {"tern": Color("cfc4a5"), "berth_crew_a": Color("a7bbad"), "berth_crew_b": Color("c6a880"), "edda": Color("b8c5c7"), "splice": Color("b6abbe")}
## Passenger windows on each side; they light as the gantries are cleared and
## the people from the depot go aboard.
const WINDOWS: int = 7
const WINDOW_DARK: Color = Color("2c3133")
const WINDOW_LIT: Color = Color("e0b273")
const CLAMP_HELD: Color = Color("c9922f")
const CLAMP_FREE: Color = Color("8eb58b")
const ENGINE_COLD: Color = Color("1c1b1a")
const ENGINE_LIT: Color = Color("d8a15e")
const HATCH_SHUT: Color = Color("9a4533")
const HATCH_OPEN: Color = Color("8eb58b")
## Clamp stations along the keel: forward of the nacelles (which cover the
## stern chocks from z -17 to -7) and at the bow chocks, so a jaw never sits
## inside a server solid, held or released.
const CLAMP_Z: Array[float] = [-5.5, 9.5]
const CLAMP_HELD_X: float = 8.0
const CLAMP_FREE_X: float = 8.6
## Every state-driven finish, made once: a Mission message (up to 20 Hz)
## only swaps these, and only when the fact behind them changes.
static var _finishes: Dictionary[String, StandardMaterial3D] = {}
var _lit_windows: int = -1
var _released: int = -1
var _engines_lit: int = -1
var _hatch_shown: int = -1
var _root: Node3D = null
var _dressing: M09Dressing = null
var _geometry: Dictionary = {}
var _crew: Dictionary[String, CivilianFigure] = {}
var _hatch_lamp: MeshInstance3D = null
var _engine_lamps: Array[MeshInstance3D] = []
var _glazing_views: Array[MeshInstance3D] = []
var _windows: Array[MeshInstance3D] = []
var _clamps: Array[Node3D] = []
var _clamp_lamps: Array[MeshInstance3D] = []
var state_applied: int = 0

func clear_map() -> void:
	_clear_presenters()
	if is_instance_valid(_dressing):
		remove_child(_dressing)
		_dressing.queue_free()
	_dressing = null

func _clear_presenters() -> void:
	_geometry.clear()
	_crew.clear()
	_engine_lamps.clear()
	_glazing_views.clear()
	_windows.clear()
	_clamps.clear()
	_clamp_lamps.clear()
	_hatch_lamp = null
	state_applied = 0
	_lit_windows = -1
	_released = -1
	_engines_lit = -1
	_hatch_shown = -1
	if is_instance_valid(_root):
		remove_child(_root)
		_root.queue_free()
	_root = null

func configure_map(info: Dictionary) -> void:
	_clear_presenters()
	if not info.get("m09") is Dictionary or not MissionState.map_error(info).is_empty():
		clear_map()
		return
	# The static berth keeps one set of rooms across a re-sent map.
	if M09Dressing.berth_layout(info):
		if not is_instance_valid(_dressing):
			_dressing = M09Dressing.new()
			_dressing.name = "BerthDressing"
			add_child(_dressing)
		_dressing.configure_map(info)
	elif is_instance_valid(_dressing):
		remove_child(_dressing)
		_dressing.queue_free()
		_dressing = null
	_geometry = MissionState.geometry_for(info)
	_root = Node3D.new()
	_root.name = "PassengerBerthDetails"
	add_child(_root)
	# Detail attaches to the authoritative hull faces, not an invented ship body.
	for index: int in range(info["solids"].size()):
		var solid: Dictionary = info["solids"][index]
		if info["presentation"]["solids"][index] == "inspection_glass":
			_glazing(solid)
		if float(solid["min_x"]) == -8.0 and float(solid["max_x"]) == 8.0 and float(solid["top"]) == 9.0 \
			and float(solid["min_z"]) == -18.0 and float(solid["max_z"]) == 18.0:
			_ship(solid)
	var control: Dictionary = info["m09"]["departure"]
	var decoration: Dictionary = info["presentation"]["decorations"][int(control["decoration"])]
	var transform: Transform3D = MapDecoration.placement(info["solids"][int(decoration["solid"])], decoration)
	_hatch_lamp = _box("BoardingStatus", transform.origin + transform.basis.z * 0.035 + transform.basis.y * 0.75, Vector3(0.9, 0.1, 0.06), Color("9a4533"), true)
	if not bool(info["m09"]["hatch_open"]):
		_impound_notice(info["solids"][int(info["m09"]["hatch"])])
	ArenaSky.mark_world(_root)

func _glazing(solid: Dictionary) -> void:
	# The seal already exists in the server. A faint neutral face makes its
	# large pressure pane legible without tinting the sky behind it.
	var size: Vector3 = Vector3(float(solid["max_x"]) - float(solid["min_x"]), 0.006, float(solid["max_z"]) - float(solid["min_z"]))
	var at: Vector3 = Vector3((float(solid["min_x"]) + float(solid["max_x"])) * 0.5, float(solid["bottom"]) - MapDecoration.OFFSET, (float(solid["min_z"]) + float(solid["max_z"])) * 0.5)
	var pane: MeshInstance3D = _box("PressureGlazing", at, size, Color(0.58, 0.6, 0.58, 0.1))
	var material: StandardMaterial3D = pane.material_override as StandardMaterial3D
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.85
	material.metallic_specular = 0.0
	_glazing_views.append(pane)

## The keel's own faces carry the name, the windows, the clamps and the
## engines' ready strips. Everything is flush or under the keel.
func _ship(hull: Dictionary) -> void:
	var port: float = float(hull["min_x"]) - 0.06
	var label: WorldSign = WorldSign.new()
	label.name = "CommonCarrierHullName"
	label.position = Vector3(port, 4.75, 7.0)
	label.rotation.y = -PI * 0.5
	label.configure("WORLD_M09_COMMON_CARRIER", Vector2(9.6, 1.25), WorldSign.PANEL_TEXT)
	_root.add_child(label)
	for side: float in [-1.0, 1.0]:
		var x: float = side * 8.03
		for index: int in range(WINDOWS):
			var z: float = -10.0 + float(index) * 3.0
			_box("CarrierWindowFrame", Vector3(side * 8.02, 7.0, z), Vector3(0.03, 1.0, 1.6), Color("3d4244"))
			_windows.append(_box("CarrierPassengerWindow", Vector3(x, 7.0, z), Vector3(0.03, 0.75, 1.3), WINDOW_DARK, true))
		# The engine throat: dark until the engines light for departure.
		var engine: MeshInstance3D = MeshInstance3D.new()
		engine.name = "CarrierEngineReady"
		var throat: CylinderMesh = CylinderMesh.new()
		throat.top_radius = 0.9
		throat.bottom_radius = 0.9
		throat.height = 0.02
		throat.radial_segments = 14
		engine.mesh = throat
		engine.position = Vector3(side * 11.0, 3.2, -17.18)
		engine.rotation.x = PI * 0.5
		engine.material_override = _finish(ENGINE_COLD)
		_root.add_child(engine)
		_engine_lamps.append(engine)
		# Clamp jaws on the keel's outboard faces: held until the cradle releases.
		for z: float in CLAMP_Z:
			var clamp: Node3D = Node3D.new()
			clamp.name = "CradleClamp"
			clamp.position = Vector3(side * CLAMP_HELD_X, 2.0, z)
			_root.add_child(clamp)
			MoonBackdrop._piece(clamp, "ClampJaw", Vector3(side * 0.16, 0.55, 0), Vector3(0.32, 1.1, 2.2), _finish(Color("8c7642"), false))
			MoonBackdrop._piece(clamp, "ClampRam", Vector3(side * 0.12, -0.35, 0), Vector3(0.24, 0.7, 0.5), _finish(Color("4a4f50"), false))
			_clamp_lamps.append(MoonBackdrop._piece(clamp, "ClampLamp", Vector3(side * 0.33, 0.95, 0.7), Vector3(0.03, 0.14, 0.3), _finish(CLAMP_HELD)))
			_clamps.append(clamp)

## Every clamp piece's world box, for the check that none sits inside a solid.
func clamp_boxes() -> Array[AABB]:
	var boxes: Array[AABB] = []
	for clamp: Node3D in _clamps:
		for piece: Node in clamp.get_children():
			var mesh: MeshInstance3D = piece as MeshInstance3D
			if mesh != null:
				boxes.append(mesh.global_transform * mesh.get_aabb())
	return boxes

## A shared state finish, made once per colour.
static func _finish(color: Color, glow: bool = true) -> StandardMaterial3D:
	var key: String = color.to_html(false) + ("g" if glow else "")
	if not _finishes.has(key):
		_finishes[key] = MoonBackdrop._material(color, glow)
	return _finishes[key]

## The hull notice the Union pasted on the closed hatch. When the hatch
## opens the MapInfo moves it and the notice is gone: Tern kept it.
func _impound_notice(hatch: Dictionary) -> void:
	var face: float = float(hatch["min_z"]) - 0.02
	var centre: float = (float(hatch["min_x"]) + float(hatch["max_x"])) * 0.5
	var y: float = MoveStep.solid_bottom(hatch) + 2.3
	_box("ImpoundNoticePaper", Vector3(centre + 1.2, y, face), Vector3(1.6, 1.15, 0.01), Color("b7ae96"))
	_box("ImpoundNoticeBorder", Vector3(centre + 1.2, y + 0.52, face - 0.004), Vector3(1.6, 0.1, 0.01), Color("8c1a1e"))
	var notice: WorldSign = WorldSign.new()
	notice.name = "ImpoundNotice"
	notice.position = Vector3(centre + 1.2, y - 0.06, face - 0.012)
	notice.rotation.y = PI
	notice.configure("WORLD_M09_IMPOUND_NOTICE", Vector2(1.4, 0.8), WorldSign.PANEL_INK)
	_root.add_child(notice)

func apply_state(state: Dictionary) -> void:
	if _geometry.is_empty() or state.get("id") != MissionState.M09_ID \
		or not MissionState.validation_error({"tick": EquipmentState.MAX_EXACT_INTEGER, "state": state}, _geometry).is_empty():
		return
	state_applied += 1
	var facts: Dictionary = state["m09"]
	for person: Dictionary in facts["crew"]:
		var id: String = str(person["id"])
		if not _crew.has(id):
			var figure: CivilianFigure = CivilianFigure.new()
			figure.name = "Passenger_" + id
			figure.configure(id, TINTS[id])
			_root.add_child(figure)
			_crew[id] = figure
		_crew[id].place_feet(_feet(person["feet"]))
	# Only a changed fact touches the fittings, and only with shared finishes.
	var hatch: int = 1 if facts["hatch_open"] else 0
	if hatch != _hatch_shown and is_instance_valid(_hatch_lamp):
		_hatch_shown = hatch
		_hatch_lamp.material_override = _finish(HATCH_OPEN if hatch == 1 else HATCH_SHUT)
	var completed: Array = facts["completed"]
	# The engines light once the hatch is won, for the departure.
	var engines: int = 1 if "hatch_cleared" in completed else 0
	if engines != _engines_lit:
		_engines_lit = engines
		for engine: MeshInstance3D in _engine_lamps:
			engine.material_override = _finish(ENGINE_LIT if engines == 1 else ENGINE_COLD)
	# Each cleared gantry puts more of the depot's people aboard.
	var lit: int = clampi((completed.size() - 2) * 2, 0, WINDOWS)
	if lit != _lit_windows:
		_lit_windows = lit
		for index: int in range(_windows.size()):
			_windows[index].material_override = _finish(WINDOW_LIT if index % WINDOWS < lit else WINDOW_DARK)
	var released: int = 1 if "clamps_released" in completed else 0
	if released != _released:
		_released = released
		for clamp: Node3D in _clamps:
			clamp.position.x = signf(clamp.position.x) * (CLAMP_FREE_X if released == 1 else CLAMP_HELD_X)
		for lamp: MeshInstance3D in _clamp_lamps:
			lamp.material_override = _finish(CLAMP_FREE if released == 1 else CLAMP_HELD)

func engines_lit() -> bool:
	return _engines_lit == 1

func clamps_released() -> bool:
	return _released == 1

static func _feet(raw: Array) -> Vector3:
	return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))

func _box(label: String, at: Vector3, size: Vector3, color: Color, glow: bool = false) -> MeshInstance3D:
	return MoonBackdrop._piece(_root, label, at, size, MoonBackdrop._material(color, glow))
