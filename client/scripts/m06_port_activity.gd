class_name M06PortActivity
extends Node3D

## Working assemblies finish the actual authored machine bodies in MapInfo.
const TRIM: float = 0.025
const Geometry = preload("res://scripts/model_geometry.gd")
var _geometry: RefCounted = Geometry.new()
var _materials: Dictionary[String, StandardMaterial3D] = {}
var _views: Dictionary[String, Texture2D] = {}
var host_count: int = 0

func build(info: Dictionary) -> void:
	name = "PortWorkAreas"
	if info.get("map_id") != 1006 or info.get("map_name") != "Port of Entry" or not info.get("solids") is Array:
		return
	var solids: Array = info["solids"]
	var platform: Dictionary = M06Workmanship._host(solids, Vector3(-8, 0, -27), Vector3(6, 0.9, -23))
	if platform.is_empty():
		return
	_edge_rails(platform, Color("737e7b"))
	var west: Dictionary = M06Workmanship._host(solids, Vector3(-6.8, 0.9, -26.5), Vector3(-1.5, 3.2, -23.5))
	var east: Dictionary = M06Workmanship._host(solids, Vector3(-0.3, 0.9, -26.5), Vector3(4.7, 2.6, -23.5))
	if not west.is_empty():
		_pressure_case(west, Color("c5c0a8"))
	if not east.is_empty():
		_pressure_case(east, Color("829c99"))
	var beam: Dictionary = M06Workmanship._host(solids, Vector3(-8, 4.3, -26), Vector3(6, 4.8, -25.3))
	if not beam.is_empty():
		_measuring_beam(beam)
	var console: Dictionary = M06Workmanship._host(solids, Vector3(7.5, 0, -25.1), Vector3(8.4, 2.1, -23.7))
	if not console.is_empty():
		_beveled_panel(console, "ScaleConsoleRecess", Vector3(7.95, 1.5, -23.685), Vector3(0.78, 0.84, 0.016), Color("515d5d"), 0.10)
		_display(console, Vector3(7.95, 1.5, -23.676), Vector2(0.64, 0.68), 0.0, "scale")
		for x: float in [7.72, 8.18]:
			_dial(console, "ScaleConsoleSelector", Vector3(x, 0.80, -23.678), 0.09, Color("c3c9b5"))
		_mark_host(console)
	for side: float in [-1.0, 1.0]:
		var low: Vector3 = Vector3(-11.95, 1.4, 15.8) if side < 0 else Vector3(11.65, 1.4, 15.8)
		var high: Vector3 = Vector3(-11.65, 2.25, 17.4) if side < 0 else Vector3(11.95, 2.25, 17.4)
		var terminal: Dictionary = M06Workmanship._host(solids, low, high)
		if not terminal.is_empty():
			var x: float = high.x + 0.016 if side < 0 else low.x - 0.016
			_display(terminal, Vector3(x, 1.825, 16.6), Vector2(1.32, 0.62), -side * PI * 0.5, "declaration")
			_mark_host(terminal)
	var luggage: Dictionary = M06Workmanship._host(solids, Vector3(-14.7, 0.65, 22.3), Vector3(-12.8, 1.8, 24.7))
	if not luggage.is_empty():
		_personal_luggage(luggage)
	var bed: Dictionary = M06Workmanship._host(solids, Vector3(-15, 0, 22), Vector3(-12.5, 0.65, 25))
	if not bed.is_empty():
		_edge_rails(bed, Color("829c99"))
	var sorter: Dictionary = M06Workmanship._host(solids, Vector3(12.5, 0, 22.8), Vector3(14.7, 2.65, 26))
	if not sorter.is_empty():
		_document_sorter(sorter)
	ArenaSky.mark_world(self)

func _pressure_case(host: Dictionary, color: Color) -> void:
	var low: Vector3 = host["low"]
	var high: Vector3 = host["high"]
	var centre: Vector3 = (low + high) * 0.5
	var width: float = high.x - low.x
	var height: float = high.y - low.y
	var steel: Color = Color("515d5d")
	# Nested chamfered panels describe a sealed lid without altering its body.
	_beveled_panel(host, "PressureLidGasket", Vector3(centre.x, centre.y, high.z + 0.008), Vector3(width - 0.10, height - 0.10, 0.010), steel, 0.24)
	_beveled_panel(host, "PressureLidBevel", Vector3(centre.x, centre.y, high.z + 0.016), Vector3(width - 0.24, height - 0.24, 0.014), color, 0.22)
	_beveled_panel(host, "RecessedPressurePanel", Vector3(centre.x, centre.y - 0.09, high.z + 0.021), Vector3(width * 0.41, height * 0.46, 0.004), steel, 0.12)
	_beveled_panel(host, "InsetPressurePanel", Vector3(centre.x, centre.y - 0.09, high.z + 0.022), Vector3(width * 0.41 - 0.10, height * 0.46 - 0.10, 0.003), color.darkened(0.12), 0.10)
	_face(host, "LidSplitSeam", Vector3(centre.x, high.y - 0.35, high.z + 0.024), Vector3(width - 0.12, 0.035, 0.002), steel)
	for fraction: float in [0.12, 0.88]:
		var x: float = lerpf(low.x, high.x, fraction)
		_face(host, "ShipmentClamp", Vector3(x, centre.y, high.z + 0.021), Vector3(0.13, height - 0.14, 0.006), steel)
		_face(host, "ShipmentTopClamp", Vector3(x, high.y + 0.012, centre.z), Vector3(0.13, 0.012, high.z - low.z), steel)
		for y: float in [low.y + 0.30, high.y - 0.29]:
			_beveled_panel(host, "LockingCamHousing", Vector3(x, y, high.z + 0.021), Vector3(0.43, 0.29, 0.006), steel, 0.07)
			_dial(host, "LockingCamPivot", Vector3(x - 0.08, y, high.z + 0.023), 0.075, Color("c3c9b5"))
			_face(host, "LockingCamLever", Vector3(x + 0.05, y + 0.045, high.z + 0.024), Vector3(0.23, 0.06, 0.002), Color("c3c9b5"))
	for fraction: float in [0.27, 0.73]:
		var x: float = lerpf(low.x, high.x, fraction)
		_beveled_panel(host, "RecessedCarryHandle", Vector3(x, centre.y + 0.07, high.z + 0.021), Vector3(0.84, 0.33, 0.006), steel.darkened(0.25), 0.08)
		_face(host, "CarryHandleGrip", Vector3(x, centre.y + 0.14, high.z + 0.024), Vector3(0.61, 0.075, 0.002), Color("c3c9b5"))
		for offset: float in [-0.31, 0.31]:
			_face(host, "CarryHandleMount", Vector3(x + offset, centre.y + 0.08, high.z + 0.024), Vector3(0.065, 0.20, 0.002), Color("c3c9b5"))
	_dial(host, "PressureGaugeRim", Vector3(centre.x, low.y + 0.29, high.z + 0.021), 0.16, steel)
	_dial(host, "PressureGaugeFace", Vector3(centre.x, low.y + 0.29, high.z + 0.0225), 0.125, Color("d8c69d"))
	var needle: MeshInstance3D = _face(host, "PressureGaugeNeedle", Vector3(centre.x + 0.025, low.y + 0.32, high.z + 0.0244), Vector3(0.10, 0.025, 0.001), steel)
	needle.rotation.z = PI * 0.18
	_mark_host(host)

func _measuring_beam(host: Dictionary) -> void:
	var face: float = -25.3
	_face(host, "CalibratedBeamRail", Vector3(-1, 4.745, face + 0.016), Vector3(13.8, 0.035, 0.012), Color("c3c9b5"))
	for index: int in range(15):
		_face(host, "BeamCalibrationTick", Vector3(-7.3 + index * 0.9, 4.67, face + 0.021), Vector3(0.035, 0.10 if index % 3 == 0 else 0.055, 0.006), Color("515d5d"))
	_beveled_panel(host, "WeighingBeamControlHead", Vector3(-1, 4.51, face + 0.014), Vector3(3.4, 0.36, 0.018), Color("343b3c"), 0.07)
	_display(host, Vector3(-1.45, 4.51, face + 0.0245), Vector2(0.52, 0.26), 0.0, "scale")
	for row: int in range(3):
		_face(host, "BeamMassReadout", Vector3(-2.22, 4.44 + row * 0.07, face + 0.024), Vector3(0.47 - row * 0.10, 0.025, 0.002), Color("d8c69d"))
	for x: float in [-0.23, 0.34]:
		_dial(host, "BeamControlSelector", Vector3(x, 4.51, face + 0.023), 0.075, Color("d8c69d"))
	for x: float in [-4.4, 2.6]:
		_dial(host, "BeamMeasuringHead", Vector3(x, 4.51, face + 0.018), 0.17, Color("515d5d"))
		_dial(host, "BeamSensorWindow", Vector3(x, 4.51, face + 0.022), 0.105, Color("82a096"))
		_face(host, "SensorTargetLine", Vector3(x, 4.51, face + 0.024), Vector3(0.12, 0.02, 0.002), Color("d8c69d"))
	_mark_host(host)

func _beveled_panel(host: Dictionary, label: String, at: Vector3, size: Vector3, color: Color, corner: float) -> void:
	var outline: Array[Vector2] = [Vector2(-size.x * 0.5 + corner, -size.y * 0.5), Vector2(size.x * 0.5 - corner, -size.y * 0.5),
		Vector2(size.x * 0.5, -size.y * 0.5 + corner), Vector2(size.x * 0.5, size.y * 0.5 - corner),
		Vector2(size.x * 0.5 - corner, size.y * 0.5), Vector2(-size.x * 0.5 + corner, size.y * 0.5),
		Vector2(-size.x * 0.5, size.y * 0.5 - corner), Vector2(-size.x * 0.5, -size.y * 0.5 + corner)]
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in range(8):
		var next: int = (index + 1) % 8
		var a: Vector3 = Vector3(outline[index].x, outline[index].y, -size.z * 0.5)
		var b: Vector3 = Vector3(outline[next].x, outline[next].y, -size.z * 0.5)
		var c: Vector3 = Vector3(outline[next].x * 0.96, outline[next].y * 0.90, size.z * 0.5)
		var d: Vector3 = Vector3(outline[index].x * 0.96, outline[index].y * 0.90, size.z * 0.5)
		var normal: Vector3 = (b - a).cross(c - a).normalized()
		if normal.z < 0:
			normal = -normal
		_geometry.quad(tool, a, b, c, d, normal)
		_geometry.triangle(tool, Vector3(0, 0, size.z * 0.5), d, c, Vector3.BACK)
	var mesh: MeshInstance3D = _geometry.instance(self, label, tool.commit(), _material(color), at)
	mesh.set_meta("m06_craft_part", label)
	_bounds(mesh, host)

func _dial(host: Dictionary, label: String, at: Vector3, radius: float, color: Color) -> void:
	var node: MeshInstance3D = MeshInstance3D.new()
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.002
	mesh.radial_segments = 8
	node.name = label
	node.mesh = mesh
	node.position = at
	node.rotation.x = PI * 0.5
	node.material_override = _material(color)
	node.set_meta("m06_craft_part", label)
	_bounds(node, host)
	add_child(node)

func _edge_rails(host: Dictionary, color: Color) -> void:
	var low: Vector3 = host["low"]
	var high: Vector3 = host["high"]
	for z: float in [low.z - 0.012, high.z + 0.012]:
		_face(host, "WorkPlatformEdge", Vector3((low.x + high.x) * 0.5, high.y - 0.12, z),
			Vector3(high.x - low.x, 0.16, 0.012), color)
	_mark_host(host)

func _personal_luggage(host: Dictionary) -> void:
	var low: Vector3 = host["low"]
	var high: Vector3 = host["high"]
	var centre: Vector3 = (low + high) * 0.5
	var panel: MeshInstance3D = _face(host, "PatchedPersonalCase", Vector3(high.x + 0.012, centre.y, centre.z),
		Vector3(0.012, high.y - low.y - 0.04, high.z - low.z - 0.04), Color.WHITE)
	panel.material_override = M06Port.possession_material(M06Port.TEXTILE)
	for fraction: float in [0.25, 0.75]:
		_face(host, "PersonalCaseStrap", Vector3(high.x + 0.022, centre.y, lerpf(low.z, high.z, fraction)),
			Vector3(0.004, high.y - low.y, 0.08), Color("746e61"))
	_mark_host(host)

func _document_sorter(host: Dictionary) -> void:
	var low: Vector3 = host["low"]
	var high: Vector3 = host["high"]
	for row: int in range(4):
		var y: float = 0.38 + row * 0.55
		_face(host, "RecordsDrawer", Vector3((low.x + high.x) * 0.5, y, low.z - 0.012),
			Vector3(high.x - low.x - 0.12, 0.48, 0.012), Color("737e7b"))
		_face(host, "RecordsDrawerHandle", Vector3((low.x + high.x) * 0.5, y, low.z - 0.022), Vector3(0.50, 0.055, 0.004), Color("c5c0a8"))
	_mark_host(host)

func _display(host: Dictionary, at: Vector3, size: Vector2, yaw: float, kind: String) -> void:
	var screen: MeshInstance3D = MeshInstance3D.new()
	screen.name = "PortWorkDisplay"
	var quad: QuadMesh = QuadMesh.new()
	quad.size = size
	screen.mesh = quad
	screen.position = at
	screen.rotation.y = yaw
	var material: StandardMaterial3D = _material(Color.WHITE).duplicate() as StandardMaterial3D
	material.albedo_texture = _display_texture(kind)
	screen.material_override = material
	_bounds(screen, host)
	add_child(screen)

func _display_texture(kind: String) -> Texture2D:
	if _views.has(kind):
		return _views[kind]
	var image: Image = Image.create(64, 32, false, Image.FORMAT_RGB8)
	image.fill(Color("253331"))
	var ink: Color = Color("afc5ad")
	if kind == "scale":
		image.fill_rect(Rect2i(12, 8, 40, 2), ink)
		image.fill_rect(Rect2i(31, 7, 2, 16), ink)
		image.fill_rect(Rect2i(20, 25, 24, 2), ink)
		for x: int in [15, 43]:
			image.fill_rect(Rect2i(x, 13, 7, 8), ink)
	else:
		image.fill_rect(Rect2i(9, 5, 20, 23), ink)
		image.fill_rect(Rect2i(12, 8, 14, 2), Color("253331"))
		image.fill_rect(Rect2i(12, 13, 14, 2), Color("253331"))
		image.fill_rect(Rect2i(12, 18, 10, 2), Color("253331"))
		for row: int in range(3):
			image.fill_rect(Rect2i(37, 8 + row * 7, 4, 4), ink)
			image.fill_rect(Rect2i(44, 9 + row * 7, 10, 2), ink)
	_views[kind] = ImageTexture.create_from_image(image)
	return _views[kind]

func _face(host: Dictionary, label: String, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh: MeshInstance3D = MoonBackdrop._piece(self, label, at, size, _material(color))
	mesh.set_meta("m06_craft_part", label)
	_bounds(mesh, host)
	return mesh

func _bounds(mesh: MeshInstance3D, host: Dictionary) -> void:
	mesh.set_meta("m06_activity_low", host["low"])
	mesh.set_meta("m06_activity_high", host["high"])

func _mark_host(_host: Dictionary) -> void:
	host_count += 1

func _material(color: Color) -> StandardMaterial3D:
	var key: String = color.to_html()
	if not _materials.has(key):
		var finish: String = "port_bone_" if color == Color("c5c0a8") else "port_metal_"
		_materials[key] = _geometry.material(finish + key, color, 0.08, 0.78)
	return _materials[key]
