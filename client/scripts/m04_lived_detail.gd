extends RefCounted

## Small possessions live on existing solid furniture; windows remain sealed.
const Geometry = preload("res://scripts/model_geometry.gd")
const WALL_RELIEF: float = 0.008
var _shape: RefCounted = Geometry.new()
var _root: Node3D
var _wood: StandardMaterial3D
var _steel: StandardMaterial3D
var _sage: StandardMaterial3D
var _bone: StandardMaterial3D
var _clay: StandardMaterial3D
var _ink: StandardMaterial3D
var _glass: StandardMaterial3D
var _cloth: StandardMaterial3D

func build(parent: Node3D, info: Dictionary) -> Node3D:
	_root = Node3D.new()
	_root.name = "InhabitedDetail"
	parent.add_child(_root)
	_wood = _shape.material("m04_wood", Color("8d6c43"))
	_steel = _shape.material("m04_worked_steel", Color("6b7570"), 0.35, 0.63)
	_sage = _shape.material("m04_sage", Color("6e8980"))
	_bone = _shape.material("m04_bone_ceramic", Color("e2d8b9"), 0.0, 0.48)
	_clay = _shape.material("m04_clay_ceramic", Color("a76343"), 0.0, 0.62)
	_ink = _shape.material("m04_ink", Color("303c38"))
	_glass = _shape.material("m04_window", Color("596e66"), 0.0, 0.39)
	_cloth = _shape.material("m04_bone_cloth", Color("bead80"))
	for raw: Variant in info["solids"]:
		var solid: Dictionary = raw
		var low: Vector3 = Vector3(solid["min_x"], solid.get("bottom", 0.0), solid["min_z"])
		var high: Vector3 = Vector3(solid["max_x"], solid.get("top", 4.0), solid["max_z"])
		# Exact authored footprints keep furniture-specific dressing out of custom
		# M04 maps with different counters, clearance or patient routes.
		if _footprint(low, high, Vector2(-13, 10), Vector2(-5, 11.5)) and is_equal_approx(high.y, 0.8):
			_repair_bench((low + high) * 0.5, high.y)
		elif _footprint(low, high, Vector2(-32, 11.5), Vector2(-25, 13)) and is_equal_approx(high.y, 0.9):
			_clinic_counter((low + high) * 0.5, high.y)
		elif _footprint(low, high, Vector2(-3, 27), Vector2(3, 30)) and is_equal_approx(high.y, 0.9):
			_meal_table((low + high) * 0.5, high.y)
		elif _footprint(low, high, Vector2(-33, -5), Vector2(-30, -3)) or _footprint(low, high, Vector2(-33, 7), Vector2(-30, 9)):
			if is_equal_approx(high.y, 0.65):
				_bed((low + high) * 0.5, high.y)
		elif _footprint(low, high, Vector2(-20, 17), Vector2(-19.5, 39)) and is_equal_approx(high.y, 5.0):
			for z: float in [21.0, 27.0, 35.0]:
				_window(Vector3(high.x, 4.05, z), PI * 0.5)
		elif _footprint(low, high, Vector2(19.5, 17), Vector2(20, 39)) and is_equal_approx(high.y, 5.0):
			for z: float in [22.0, 27.5, 35.5]:
				_window(Vector3(low.x, 4.05, z), -PI * 0.5)
		elif _footprint(low, high, Vector2(-20, 39), Vector2(20, 39.5)) and is_equal_approx(high.y, 5.0):
			for x: float in [-10.5, -3.5, 4.0]:
				_window(Vector3(x, 4.05, low.z), PI)
	_merge()
	return _root

static func _footprint(low: Vector3, high: Vector3, expected_low: Vector2, expected_high: Vector2) -> bool:
	return Vector2(low.x, low.z).is_equal_approx(expected_low) and Vector2(high.x, high.z).is_equal_approx(expected_high)

func _marker(label: String, at: Vector3) -> void:
	var marker: Node3D = Node3D.new()
	marker.name = label if not _root.has_node(NodePath(label)) else "%s_%d" % [label, _root.get_child_count()]
	marker.position = at
	_root.add_child(marker)

func _repair_bench(center: Vector3, top: float) -> void:
	var at: Vector3 = Vector3(center.x, top, center.z)
	_marker("SharedChargingBench", at)
	# Hollow spools, coiled cable, a opened contact tray and a worn iron rest.
	for index: int in range(3):
		var spool: Vector3 = at + Vector3(-2.9 + index * 0.47, 0.115, 0.08)
		var profile: PackedVector2Array = PackedVector2Array([Vector2(-0.11, 0.045), Vector2(-0.11, 0.15), Vector2(-0.08, 0.15), Vector2(-0.075, 0.095), Vector2(0.075, 0.095), Vector2(0.08, 0.15), Vector2(0.11, 0.15), Vector2(0.11, 0.045)])
		var node: MeshInstance3D = _shape.lathe(_root, "CableSpool", profile, _clay if index == 1 else _sage, spool, 16)
		node.rotation.x = PI * 0.5
	for index: int in range(4):
		var points: PackedVector3Array = []
		for step: int in range(25):
			var angle: float = TAU * float(step) / 24.0
			points.append(at + Vector3(-0.85 + cos(angle) * (0.25 + index * 0.018), 0.026 + index * 0.018, sin(angle) * 0.23))
		_shape.pipe(_root, "ChargingCable", points, 0.015, _ink)
	_shape.block(_root, "ChargingDock", Vector3(0.92, 0.11, 0.44), _sage, at + Vector3(0.15, 0.06, 0.0))
	for x: float in [-0.13, 0.13, 0.39]:
		_shape.block(_root, "ContactSocket", Vector3(0.13, 0.015, 0.09), _ink, at + Vector3(x, 0.12, -0.03))
	_tray(at + Vector3(1.33, 0.014, 0.04), Vector2(0.66, 0.39), _steel)
	for index: int in range(5):
		_shape.cylinder(_root, "ContactSleeve", 0.025, 0.14, _bone, at + Vector3(1.08 + index * 0.09, 0.053, 0.01))
	_shape.rod(_root, "RepairIron", at + Vector3(2.12, 0.055, -0.14), at + Vector3(2.57, 0.055, 0.16), 0.022, _steel)
	_shape.block(_root, "IronHandle", Vector3(0.18, 0.065, 0.07), _wood, at + Vector3(2.22, 0.06, -0.065)).rotation.y = -0.55

func _clinic_counter(center: Vector3, top: float) -> void:
	var at: Vector3 = Vector3(center.x, top, center.z)
	_marker("MaintainedCareStation", at)
	_tray(at + Vector3(-1.4, 0.012, -0.03), Vector2(0.82, 0.5), _bone)
	for index: int in range(3):
		_bowl(at + Vector3(-1.62 + index * 0.22, 0.03, -0.035), 0.08, _bone)
	for index: int in range(3):
		var jar: Vector3 = at + Vector3(0.25 + index * 0.32, 0.0, 0.15)
		_shape.hull(_root, "CareJar", PackedVector3Array([Vector3(0, 0.075, 0.075), Vector3(0.015, 0.095, 0.095), Vector3(0.19, 0.095, 0.095), Vector3(0.21, 0.065, 0.065)]), _sage, jar, 12)
		_shape.cylinder(_root, "JarLid", 0.075, 0.035, _bone, jar + Vector3(0, 0.227, 0)).rotation.x = PI * 0.5
	_shape.block(_root, "FoldedCareLinen", Vector3(0.72, 0.075, 0.48), _cloth, at + Vector3(1.8, 0.042, 0.04))
	_shape.block(_root, "LinenFold", Vector3(0.66, 0.045, 0.42), _bone, at + Vector3(1.77, 0.10, 0.05))

func _bed(center: Vector3, top: float) -> void:
	var at: Vector3 = Vector3(center.x, top, center.z)
	_marker("ClinicMadeBed", at)
	_shape.block(_root, "BedLinen", Vector3(2.86, 0.025, 1.86), _bone, at + Vector3(0, 0.014, 0))
	_shape.block(_root, "FoldedBlanket", Vector3(1.25, 0.055, 1.8), _sage, at + Vector3(0.7, 0.052, 0))
	_shape.block(_root, "CarePillow", Vector3(0.66, 0.12, 1.25), _cloth, at + Vector3(-0.92, 0.075, 0))

func _meal_table(center: Vector3, top: float) -> void:
	var at: Vector3 = Vector3(center.x, top, center.z)
	_marker("InterruptedSharedMeal", at)
	# Different bowls and cups indicate individuals, not identical issued kits.
	for index: int in range(4):
		var x: float = -2.18 + index * 1.35
		var z: float = -0.72 if index % 2 == 0 else 0.72
		_bowl(at + Vector3(x, 0.01, z), 0.21, _bone if index % 2 == 0 else _clay)
		_mug(at + Vector3(x + 0.35, 0.015, z * 0.88), _sage if index == 2 else _bone)
		_shape.rod(_root, "MealSpoon", at + Vector3(x - 0.32, 0.025, z - 0.12), at + Vector3(x - 0.3, 0.025, z + 0.17), 0.012, _steel)
	_bowl(at + Vector3(0.25, 0.012, 0), 0.33, _clay)
	_shape.block(_root, "SharedBreadBoard", Vector3(0.82, 0.035, 0.52), _wood, at + Vector3(-0.9, 0.028, 0.0))
	_shape.hull(_root, "BreadLoaf", PackedVector3Array([Vector3(0, 0.29, 0.12), Vector3(0.06, 0.31, 0.13), Vector3(0.13, 0.23, 0.105), Vector3(0.16, 0.08, 0.06)]), _cloth, at + Vector3(-0.9, 0.045, 0), 12)

func _bowl(at: Vector3, radius: float, finish: StandardMaterial3D) -> void:
	var vessel: MeshInstance3D = _shape.lathe(_root, "CeramicBowl", PackedVector2Array([Vector2(0, radius * 0.4), Vector2(0.02, radius * 0.64), Vector2(radius * 0.46, radius), Vector2(radius * 0.49, radius), Vector2(radius * 0.49, radius * 0.92), Vector2(0.035, radius * 0.56), Vector2(0.025, 0)]), finish, at, 16)
	vessel.rotation.x = -PI * 0.5

func _mug(at: Vector3, finish: StandardMaterial3D) -> void:
	var vessel: MeshInstance3D = _shape.lathe(_root, "CeramicMug", PackedVector2Array([Vector2(0, 0), Vector2(0, 0.065), Vector2(0.14, 0.075), Vector2(0.15, 0.075), Vector2(0.15, 0.058), Vector2(0.018, 0.055), Vector2(0.018, 0)]), finish, at, 16)
	vessel.rotation.x = -PI * 0.5
	_shape.pipe(_root, "MugHandle", PackedVector3Array([at + Vector3(0.065, 0.115, 0), at + Vector3(0.115, 0.12, 0), at + Vector3(0.125, 0.06, 0), at + Vector3(0.063, 0.045, 0)]), 0.014, finish)

func _tray(at: Vector3, size: Vector2, finish: StandardMaterial3D) -> void:
	_shape.block(_root, "TrayBase", Vector3(size.x, 0.02, size.y), finish, at)
	for side: float in [-1.0, 1.0]:
		_shape.block(_root, "TrayRim", Vector3(size.x, 0.04, 0.02), finish, at + Vector3(0, 0.018, size.y * side * 0.5))
		_shape.block(_root, "TrayRim", Vector3(0.02, 0.04, size.y), finish, at + Vector3(size.x * side * 0.5, 0.018, 0))

func _window(at: Vector3, yaw: float) -> void:
	var start: int = _root.get_child_count()
	# The 8 mm surface treatment covers a real wall, with opaque glass. It
	# neither cuts a window opening nor projects furniture into balcony lanes.
	_shape.block(_root, "SealedWindowGlass", Vector3(1.9, 1.5, 0.002), _glass, Vector3(0, 0, 0.0015))
	for side: float in [-1.0, 1.0]:
		_shape.block(_root, "WindowFrame", Vector3(2.0, 0.075, 0.006), _wood, Vector3(0, side * 0.75, 0.004))
		_shape.block(_root, "WindowFrame", Vector3(0.075, 1.5, 0.006), _wood, Vector3(side * 0.96, 0, 0.004))
		for fold: int in range(3):
			_shape.block(_root, "DomesticCurtain", Vector3(0.08, 1.37, 0.002), _cloth, Vector3(side * (0.72 + fold * 0.075), 0, 0.003 + float(fold % 2) * 0.001))
	_shape.block(_root, "WindowMullion", Vector3(0.05, 1.5, 0.007), _sage, Vector3(0, 0, 0.0045))
	var transform_value: Transform3D = Transform3D(Basis(Vector3.UP, yaw), at)
	for index: int in range(start, _root.get_child_count()):
		var node: Node3D = _root.get_child(index)
		node.transform = transform_value * node.transform
	_marker("SealedDomesticWindow", at)

func _merge() -> void:
	var part_count: int = 0
	for child: Node in _root.get_children():
		if child is MeshInstance3D:
			part_count += 1
	var surface_count: int = 0
	if part_count > 0:
		_shape.merge(_root)
		var visible: MeshInstance3D = _root.get_node("FixtureMesh")
		visible.name = "MergedPossessions"
		visible.layers = ArenaSky.WORLD_LAYERS
		surface_count = visible.mesh.get_surface_count()
	_root.set_meta("source_parts", part_count)
	_root.set_meta("finish_surfaces", surface_count)