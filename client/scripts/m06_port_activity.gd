class_name M06PortActivity
extends Node3D

## Working assemblies finish the actual authored machine bodies in MapInfo.
const TRIM: float = 0.025
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
		_face(beam, "WeighingGantryIdentification", Vector3(-1, 4.55, -25.284), Vector3(3.6, 0.32, 0.012), Color("343b3c"))
		for index: int in range(3):
			_face(beam, "GantryMassScale", Vector3(-2.0 + index, 4.55, -25.280), Vector3(0.45, 0.09, 0.006), Color("d8c69d"))
		_mark_host(beam)
	var console: Dictionary = M06Workmanship._host(solids, Vector3(7.5, 0, -25.1), Vector3(8.4, 2.1, -23.7))
	if not console.is_empty():
		_display(console, Vector3(7.95, 1.5, -23.684), Vector2(0.64, 0.68), 0.0, "scale")
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
	_face(host, "PressureShipmentFace", Vector3(centre.x, centre.y, high.z + 0.012), Vector3(width - 0.12, high.y - low.y - 0.12, 0.012), color)
	for fraction: float in [0.16, 0.84]:
		var x: float = lerpf(low.x, high.x, fraction)
		_face(host, "ShipmentClamp", Vector3(x, centre.y, high.z + 0.020), Vector3(0.14, high.y - low.y, 0.008), Color("515d5d"))
		_face(host, "ShipmentTopClamp", Vector3(x, high.y + 0.012, centre.z), Vector3(0.14, 0.012, high.z - low.z), Color("515d5d"))
	_face(host, "ShipmentPressureSeal", Vector3(centre.x, centre.y, high.z + 0.020), Vector3(1.6, 0.65, 0.008), Color("515d5d"))
	for offset: float in [-0.58, 0.58]:
		_face(host, "PressureSealBolt", Vector3(centre.x + offset, centre.y, high.z + 0.023), Vector3(0.07, 0.09, 0.002), Color("c3c9b5"))
	_mark_host(host)

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
		_materials[key] = MoonBackdrop._material(color)
	return _materials[key]
