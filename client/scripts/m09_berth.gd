class_name M09Berth
extends Node3D

## The ship's details add no collision. Current people and feet come only
## from accepted mission facts; named Tern and Edda share their M10 live skins.
const TINTS: Dictionary[String, Color] = {"tern": Color("cfc4a5"), "berth_crew_a": Color("a7bbad"), "berth_crew_b": Color("c6a880"), "edda": Color("b8c5c7"), "splice": Color("b6abbe")}
var _root: Node3D = null
var _geometry: Dictionary = {}
var _crew: Dictionary[String, CivilianFigure] = {}
var _hatch_lamp: MeshInstance3D = null
var _engine_lamps: Array[MeshInstance3D] = []
var _glazing_views: Array[MeshInstance3D] = []
var state_applied: int = 0

func clear_map() -> void:
	_geometry.clear()
	_crew.clear()
	_engine_lamps.clear()
	_glazing_views.clear()
	_hatch_lamp = null
	state_applied = 0
	if is_instance_valid(_root):
		remove_child(_root)
		_root.queue_free()
	_root = null

func configure_map(info: Dictionary) -> void:
	clear_map()
	if not info.get("m09") is Dictionary or not MissionState.map_error(info).is_empty():
		return
	_geometry = MissionState.geometry_for(info)
	_root = Node3D.new()
	_root.name = "PassengerBerthDetails"
	add_child(_root)
	var stern: Dictionary = {}
	for candidate: Dictionary in info["solids"]:
		if float(candidate["min_x"]) == -8.0 and float(candidate["max_x"]) == 8.0 \
			and float(candidate["min_z"]) == -22.0 and float(candidate["max_z"]) == -18.0 \
			and float(candidate["bottom"]) == 3.0 and float(candidate["top"]) == 12.0:
			stern = candidate
	# Detail attaches to the authoritative hull faces, not an invented ship body.
	for index: int in range(info["solids"].size()):
		var solid: Dictionary = info["solids"][index]
		if info["presentation"]["solids"][index] == "inspection_glass":
			_glazing(solid)
		if float(solid["min_x"]) == -8.0 and float(solid["max_x"]) == 8.0 and float(solid["top"]) == 9.0 \
			and float(solid["min_z"]) == -18.0 and float(solid["max_z"]) == 18.0:
			_ship(solid, stern)
	var control: Dictionary = info["m09"]["departure"]
	var decoration: Dictionary = info["presentation"]["decorations"][int(control["decoration"])]
	var transform: Transform3D = MapDecoration.placement(info["solids"][int(decoration["solid"])], decoration)
	_hatch_lamp = _box("BoardingStatus", transform.origin + transform.basis.z * 0.035 + transform.basis.y * 0.75, Vector3(0.9, 0.1, 0.06), Color("9a4533"), true)
	ArenaSky.mark_world(_root)

func _glazing(solid: Dictionary) -> void:
	# The seal already exists in the server. A restrained face tint makes its
	# large pressure pane legible without changing glass in other venues.
	var size: Vector3 = Vector3(float(solid["max_x"]) - float(solid["min_x"]), 0.006, float(solid["max_z"]) - float(solid["min_z"]))
	var at: Vector3 = Vector3((float(solid["min_x"]) + float(solid["max_x"])) * 0.5, float(solid["bottom"]) - MapDecoration.OFFSET, (float(solid["min_z"]) + float(solid["max_z"])) * 0.5)
	var pane: MeshInstance3D = _box("PressureGlazing", at, size, Color(0.35, 0.55, 0.58, 0.22))
	var material: StandardMaterial3D = pane.material_override as StandardMaterial3D
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = Color(0.045, 0.075, 0.078)
	material.emission_energy_multiplier = 0.7
	material.roughness = 0.85
	material.metallic_specular = 0.0
	_glazing_views.append(pane)

func _ship(hull: Dictionary, stern: Dictionary = {}) -> void:
	var width: float = float(hull["max_x"]) - float(hull["min_x"])
	var front_host: Dictionary = hull if stern.is_empty() else stern
	var front: float = float(front_host["min_z"]) - 0.02
	_box("CarrierHullStripe", Vector3(0, maxf(2.2, float(front_host["bottom"]) + 0.2), front), Vector3(width, 0.22, 0.025), Color("778f8a"))
	var label: WorldSign = WorldSign.new()
	label.name = "CommonCarrierHullName"
	label.position = Vector3(0, 6.7, front - 0.015)
	label.rotation.y = PI
	label.configure("WORLD_M09_COMMON_CARRIER", Vector2(11.0, 1.7), MenuTheme.BONE)
	_root.add_child(label)
	for side: float in [-1.0, 1.0]:
		var x: float = side * 8.02
		_box("CarrierSideStripe", Vector3(x, 2.2, 0), Vector3(0.025, 0.22, 36), Color("778f8a"))
		for index: int in range(7):
			_box("CarrierPassengerWindow", Vector3(x, 6.2, -10 + index * 3.0), Vector3(0.03, 0.8, 1.4), Color("728d91"))
		var engine: MeshInstance3D = _box("CarrierEngineReady", Vector3(side * 11, 2.8, -17.025), Vector3(3, 0.55, 0.035), Color("473c32"), true)
		_engine_lamps.append(engine)

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
	if is_instance_valid(_hatch_lamp):
		_hatch_lamp.material_override = MoonBackdrop._material(Color("8eb58b") if facts["hatch_open"] else Color("9a4533"), true)
	for engine: MeshInstance3D in _engine_lamps:
		engine.material_override = MoonBackdrop._material(Color("d8a15e") if facts["completed"].size() >= 8 else Color("473c32"), true)

static func _feet(raw: Array) -> Vector3:
	return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))

func _box(label: String, at: Vector3, size: Vector3, color: Color, glow: bool = false) -> MeshInstance3D:
	return MoonBackdrop._piece(_root, label, at, size, MoonBackdrop._material(color, glow))
