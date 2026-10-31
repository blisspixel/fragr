class_name ComplianceYard
extends Node3D

## Compliance Yard (map 2): a working Union records and inspection block at
## night. Each room's floor is coded in the Office's own institutional paint
## (graphite for the court, oxide for inspection, archive green for the
## records, dark for the lockup), with painted lane lines, queue boxes, stop
## bars and hatched door thresholds, and caged work lamps hung from the wall
## tops light the rooms people pass through.
##
## Presentation only: every mark lies flat on the floor and every lamp hangs
## overhead from a wall top; nothing is collision, cover or a floor, and the
## server's solids still own every shot and step. Coordinates are the plan's,
## built at the server's SCALE (compliance_yard.rs).
const TownDressing = preload("res://scripts/low_water_dressing.gd")
const SCALE: float = 0.95
const FLOOR_Y: float = 0.006
## Room floors: plan rectangle (min x, min z, max x, max z) and its paint.
const ROOMS: Array[Dictionary] = [
	{"rect": Rect2(-36, -36, 24, 24), "tint": Color("6f7a70")}, # records, archive green-grey
	{"rect": Rect2(-12, -36, 26, 20), "tint": Color("7d6c62")}, # inspection, oxide
	{"rect": Rect2(14, -36, 22, 28), "tint": Color("5c6064")}, # lockup, graphite
	{"rect": Rect2(-36, -12, 24, 26), "tint": Color("7a7a72")}, # intake, worn civic
	{"rect": Rect2(-12, -16, 26, 28), "tint": Color("6a6d70")}, # court, graphite
	{"rect": Rect2(14, -8, 22, 22), "tint": Color("6c6f6a")}, # relay
	{"rect": Rect2(-36, 14, 28, 22), "tint": Color("76726a")}, # weighbridge
	{"rect": Rect2(-8, 12, 20, 24), "tint": Color("7a7670")}, # offices
	{"rect": Rect2(12, 14, 24, 22), "tint": Color("686660")}, # dock
]
const PAINT_YELLOW: Color = Color("c9a23a")
const PAINT_RED: Color = Color("7c2020")
const PAINT_WHITE: Color = Color("bdb8aa")
## Hung work lamps (plan x, z, the wall top they hang from, reach).
const LAMPS: Array[Dictionary] = [
	{"at": Vector2(-2, 11.3), "reach": Vector3(0, 0, -1)},
	{"at": Vector2(13.3, -12), "reach": Vector3(-1, 0, 0)},
	{"at": Vector2(-11.3, -2), "reach": Vector3(1, 0, 0)},
	{"at": Vector2(1, -16.7), "reach": Vector3(0, 0, -1)},
]
const LAMP_HEIGHT: float = 4.3

var _materials: Dictionary[String, Material] = {}

static func applies(info: Dictionary) -> bool:
	return int(info.get("map_id", -1)) == 2 and str(info.get("map_name", "")).strip_edges().to_lower() == "compliance yard"

func build(_info: Dictionary) -> void:
	name = "ComplianceYardDressing"
	add_to_group(&"compliance_yard")
	for room: Dictionary in ROOMS:
		var rect: Rect2 = room["rect"]
		_floor(rect.grow(-0.35), _tinted(room["tint"]), FLOOR_Y)
	_court_marks()
	_intake_queue()
	_thresholds()
	for index: int in range(LAMPS.size()):
		_lamp(LAMPS[index]["at"], LAMPS[index]["reach"], index)

func _tinted(colour: Color) -> Material:
	var key: String = colour.to_html(false)
	if _materials.has(key):
		return _materials[key]
	var material: Material = ArenaMaterials.authored("concrete", "compliance_yard")
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter("surface_color", colour)
		(material as ShaderMaterial).set_shader_parameter("surface_kind", 0)
	_materials[key] = material
	return material

func _paint(colour: Color) -> Material:
	var key: String = "paint" + colour.to_html(false)
	if _materials.has(key):
		return _materials[key]
	var paint: StandardMaterial3D = StandardMaterial3D.new()
	paint.albedo_color = colour
	paint.roughness = 0.95
	paint.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_materials[key] = paint
	return paint

## A flat rectangle on the floor at plan coordinates.
func _floor(rect: Rect2, finish: Material, height: float) -> MeshInstance3D:
	var view: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = rect.size * SCALE
	view.mesh = plane
	view.material_override = finish
	var centre: Vector2 = rect.get_center() * SCALE
	view.position = Vector3(centre.x, height, centre.y)
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(view)
	return view

## The two inspection lanes: yellow edge lines, a red stop bar at the
## inspector's desk and arrows of short dashes pointing to it.
func _court_marks() -> void:
	var yellow: Material = _paint(PAINT_YELLOW)
	for z: float in [-2.3, 5.3]:
		_floor(Rect2(-3.0, z - 0.06, 9.0, 0.12), yellow, FLOOR_Y * 2.0)
	for lane: float in [0.0, 3.0]:
		_floor(Rect2(5.2, lane - 1.3, 0.25, 2.6), _paint(PAINT_RED), FLOOR_Y * 2.0)
		for dash: int in range(4):
			_floor(Rect2(-2.6 + float(dash) * 1.7, lane - 0.06, 0.9, 0.12), _paint(PAINT_WHITE), FLOOR_Y * 2.0)
	# A waiting box at the lanes' mouth.
	for edge: Rect2 in [Rect2(-5.0, -2.3, 0.12, 7.6), Rect2(-5.0, -2.3, 2.0, 0.12), Rect2(-5.0, 5.18, 2.0, 0.12)]:
		_floor(edge, yellow, FLOOR_Y * 2.0)

## Numbered queue boxes between the intake rails: painted squares, no words.
func _intake_queue() -> void:
	var white: Material = _paint(PAINT_WHITE)
	for row: float in [-3.5, 1.5, 6.5]:
		for column: int in range(5):
			var x: float = -32.0 + float(column) * 2.3
			for edge: Rect2 in [Rect2(x, row - 0.8, 1.4, 0.08), Rect2(x, row + 0.72, 1.4, 0.08), Rect2(x, row - 0.8, 0.08, 1.6), Rect2(x + 1.32, row - 0.8, 0.08, 1.6)]:
				_floor(edge, white, FLOOR_Y * 2.0)

## Hatched yellow bars across the court's doorways: keep the door clear.
func _thresholds() -> void:
	var yellow: Material = _paint(PAINT_YELLOW)
	var black: Material = _paint(Color("26262a"))
	# (plan centre, along x?) for the court's doors and the hall's.
	for door: Array in [[Vector2(-9, -16), true], [Vector2(7.5, -16), true], [Vector2(3, 12), true], [Vector2(-12, 6), false], [Vector2(14, -5.5), false]]:
		var at: Vector2 = door[0]
		var along_x: bool = door[1]
		for stripe: int in range(5):
			var offset: float = -2.0 + float(stripe) * 0.9
			var rect: Rect2 = Rect2(at.x + offset, at.y - 0.6, 0.45, 1.2) if along_x else Rect2(at.x - 0.6, at.y + offset, 1.2, 0.45)
			_floor(rect, yellow if stripe % 2 == 0 else black, FLOOR_Y * 3.0)

## A caged work lamp on a bracket from a wall top, lighting the floor.
func _lamp(plan: Vector2, reach: Vector3, index: int) -> void:
	var iron: StandardMaterial3D = _paint(Color("1e2124")) as StandardMaterial3D
	var bulb: StandardMaterial3D = StandardMaterial3D.new()
	bulb.albedo_color = Color("fff1d2")
	bulb.emission_enabled = true
	bulb.emission = Color("ffe2a8")
	bulb.emission_energy_multiplier = 2.2
	var node: Node3D = Node3D.new()
	node.name = "WorkLamp%d" % index
	node.position = Vector3(plan.x * SCALE, LAMP_HEIGHT, plan.y * SCALE)
	add_child(node)
	TownDressing._box_view(node, Vector3(0.1, 0.1, 0.1) + reach.abs() * 1.2, reach * 0.6, iron)
	TownDressing._box_view(node, Vector3(0.55, 0.22, 0.55), reach * 1.2 - Vector3(0, 0.12, 0), iron)
	TownDressing._box_view(node, Vector3(0.4, 0.05, 0.4), reach * 1.2 - Vector3(0, 0.25, 0), bulb)
	var light: SpotLight3D = SpotLight3D.new()
	light.name = "WorkLight"
	light.light_color = Color("ffe0ad")
	light.light_energy = 4.0
	light.spot_range = 14.0
	light.spot_angle = 62.0
	light.spot_attenuation = 0.8
	light.shadow_enabled = true
	light.position = reach * 1.2 - Vector3(0, 0.3, 0)
	light.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	node.add_child(light)
