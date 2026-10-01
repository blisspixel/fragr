class_name ArenaWater
extends Node3D

## Shallow cosmetic floor water. No collision, depth, swimming or shot authority.
const SHADER: Shader = preload("res://assets/shaders/arena_water.gdshader")
const HEIGHT: float = 0.014
const MAX_PATCHES: int = 4
const PLACEMENTS: Array[Dictionary] = [
	{"id": "TramWash", "center": Vector2(5.0, -14.0), "size": Vector2(3.5, 2.2)},
	{"id": "MarketWash", "center": Vector2(4.0, 11.0), "size": Vector2(4.0, 2.4)},
	{"id": "CourtWash", "center": Vector2(-8.0, 25.0), "size": Vector2(5.0, 3.0)},
]
var patches: Array[MeshInstance3D] = []
var _materials: Array[ShaderMaterial] = []
var _clock: float = 0.0
var _frame: int = -1

func build(info: Dictionary) -> void:
	name = "ShallowWater"
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	patches.clear()
	_materials.clear()
	_clock = 0.0
	_frame = -1
	if info.get("map_id") == 1005 and info.get("m05") is Dictionary and MissionState.map_error(info).is_empty():
		for placement: Dictionary in [
			{"id": "WorkshopRunoff", "center": Vector2(-19.0, -10.0), "size": Vector2(2.4, 3.0)},
			{"id": "TrenchRunoff", "center": Vector2(-4.0, 15.0), "size": Vector2(2.0, 3.0)},
			{"id": "FreightRunoff", "center": Vector2(14.0, 36.0), "size": Vector2(2.0, 3.0)}]:
			add_patch(placement["id"], placement["center"], placement["size"], float(info["half_extent"]), info["solids"])
		return
	if not MapGeometry.validation_error(info).is_empty() or info.get("map_id") != 1004 \
		or not info.get("m04") is Dictionary or not info["m04"].get("clinic_open") is bool \
		or float(info["half_extent"]) != 40.0 or not _registered_venue(info):
		return
	for placement: Dictionary in PLACEMENTS:
		add_patch(placement["id"], placement["center"], placement["size"], float(info["half_extent"]), info["solids"])

## Reusable on known flat floor, refuse solids even when they are raised.
func add_patch(label: String, center: Vector2, size: Vector2, half: float, solids: Array) -> bool:
	if patches.size() >= MAX_PATCHES or label.is_empty() or not center.is_finite() or not size.is_finite() \
		or not is_finite(half) or half < 2.0 or half > MapGeometry.MAX_HALF or solids.size() > MapGeometry.MAX_SOLIDS \
		or size.x < 0.5 or size.y < 0.5 or size.x > 8.0 or size.y > 8.0:
		return false
	var low: Vector2 = center - size * 0.5
	var high: Vector2 = center + size * 0.5
	if low.x <= -half + 0.5 or high.x >= half - 0.5 or low.y <= -half + 0.5 or high.y >= half - 0.5:
		return false
	for existing: MeshInstance3D in patches:
		var plane: PlaneMesh = existing.mesh as PlaneMesh
		var placed: Vector2 = Vector2(existing.position.x, existing.position.z)
		var gap: Vector2 = (center - placed).abs() - (size + plane.size) * 0.5
		if gap.x < 0.0 and gap.y < 0.0:
			return false
	for solid: Variant in solids:
		if not solid is Dictionary or not _finite_rect(solid):
			return false
		if low.x < float(solid["max_x"]) + 0.05 and high.x > float(solid["min_x"]) - 0.05 \
			and low.y < float(solid["max_z"]) + 0.05 and high.y > float(solid["min_z"]) - 0.05:
			return false
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("patch_size", size)
	material.set_shader_parameter("phase", float(patches.size()) * 1.7)
	var water: MeshInstance3D = _plane(label, Vector3(center.x, HEIGHT, center.y), size, material)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	patches.append(water)
	_materials.append(material)
	_dress(center, size)
	return true

static func _finite_rect(solid: Dictionary) -> bool:
	for key: String in ["min_x", "max_x", "min_z", "max_z"]:
		if not MapGeometry._number(solid.get(key)):
			return false
	return float(solid["min_x"]) < float(solid["max_x"]) and float(solid["min_z"]) < float(solid["max_z"])

static func _registered_venue(info: Dictionary) -> bool:
	var presentation: Variant = info.get("presentation")
	if not presentation is Dictionary or not presentation.get("decorations") is Array:
		return false
	var found: Dictionary[String, bool] = {}
	for decoration: Dictionary in presentation["decorations"]:
		var solid: Dictionary = info["solids"][int(decoration["solid"])]
		if decoration["kind"] == "m04_notice_board" and absf(float(solid["min_x"]) + 3.0) < 0.01 \
			and absf(float(solid["min_z"]) + 17.0) < 0.01:
			found["board"] = true
		if decoration["kind"] == "m04_market_canvas":
			found["market"] = true
		if decoration["kind"] == "m04_water_tank" and absf(float(solid["min_x"]) + 18.0) < 0.01 \
			and absf(float(solid["min_z"]) - 35.0) < 0.01:
			found["tank"] = true
	return found.size() == 3

func _dress(center: Vector2, size: Vector2) -> void:
	var iron: StandardMaterial3D = _material(Color("344741"))
	var brass: StandardMaterial3D = _material(Color("a18b66"))
	var paper: StandardMaterial3D = _material(Color("baae91"))
	var drain: Vector3 = Vector3(center.x + size.x * 0.34, 0.018, center.y + size.y * 0.18)
	_plane("DrainRecess", drain, Vector2(0.25, 0.9), iron)
	for index: int in range(7):
		_plane("DrainBar", drain + Vector3(0, 0.002, -0.36 + float(index) * 0.12), Vector2(0.21, 0.035), brass)
	for index: int in range(2):
		var litter: MeshInstance3D = _plane("DampPaper", Vector3(center.x - size.x * 0.28 + float(index) * 0.31,
			0.017, center.y - size.y * 0.24), Vector2(0.17, 0.23), paper)
		litter.rotation.y = float(index) * 0.8 + 0.2

func _plane(label: String, at: Vector3, size: Vector2, material: Material) -> MeshInstance3D:
	var mesh: PlaneMesh = PlaneMesh.new()
	mesh.size = size
	var view: MeshInstance3D = MeshInstance3D.new()
	view.name = label
	view.mesh = mesh
	view.position = at
	view.material_override = material
	view.layers = ArenaSky.WORLD_LAYERS
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(view)
	return view

static func _material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return material

func set_ripple_time(seconds: float) -> void:
	if not is_finite(seconds) or seconds < 0.0:
		return
	_clock = fmod(seconds, 32.0)
	_frame = int(_clock * 8.0)
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter("ripple_time", _clock)

func _process(delta: float) -> void:
	if not is_finite(delta):
		return
	_clock = fmod(_clock + maxf(delta, 0.0), 32.0)
	if int(_clock * 8.0) != _frame:
		set_ripple_time(_clock)
